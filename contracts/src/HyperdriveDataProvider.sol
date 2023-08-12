// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveStorage } from "./HyperdriveStorage.sol";
import { IHyperdrive } from "./interfaces/IHyperdrive.sol";
import { AssetId } from "./libraries/AssetId.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { HyperdriveMath } from "./libraries/HyperdriveMath.sol";
import { MultiTokenDataProvider } from "./token/MultiTokenDataProvider.sol";

/// @author DELV
/// @title HyperdriveDataProvider
/// @notice The Hyperdrive data provider.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveDataProvider is
    HyperdriveStorage,
    MultiTokenDataProvider
{
    using FixedPointMath for uint256;

    // solhint-disable no-empty-blocks
    /// @notice Initializes Hyperdrive's data provider.
    /// @param _config The configuration of the Hyperdrive pool.
    constructor(
        IHyperdrive.PoolConfig memory _config
    ) HyperdriveStorage(_config) {}

    /// Yield Source ///

    ///@notice Loads the share price from the yield source
    ///@return sharePrice The current share price.
    function _pricePerShare()
        internal
        view
        virtual
        returns (uint256 sharePrice);

    /// Getters ///

    /// @notice Gets the base token.
    /// @return The base token.
    function baseToken() external view returns (address) {
        _revert(abi.encode(_baseToken));
    }

    /// @notice Gets a specified checkpoint.
    /// @param _checkpointId The checkpoint ID.
    /// @return The checkpoint.
    function getCheckpoint(
        uint256 _checkpointId
    ) external view returns (IHyperdrive.Checkpoint memory) {
        _revert(abi.encode(_checkpoints[_checkpointId]));
    }

    /// @notice Gets the pool's configuration parameters.
    /// @dev These parameters are immutable, so this should only need to be
    ///      called once.
    /// @return The PoolConfig struct.
    function getPoolConfig()
        external
        view
        returns (IHyperdrive.PoolConfig memory)
    {
        _revert(
            abi.encode(
                IHyperdrive.PoolConfig({
                    baseToken: _baseToken,
                    initialSharePrice: _initialSharePrice,
                    minimumShareReserves: _minimumShareReserves,
                    positionDuration: _positionDuration,
                    checkpointDuration: _checkpointDuration,
                    timeStretch: _timeStretch,
                    governance: _governance,
                    feeCollector: _feeCollector,
                    fees: IHyperdrive.Fees(_curveFee, _flatFee, _governanceFee),
                    updateGap: _updateGap,
                    oracleSize: _buffer.length
                })
            )
        );
    }

    /// @notice Gets info about the pool's reserves and other state that is
    ///         important to evaluate potential trades.
    /// @return The PoolInfo struct.
    function getPoolInfo() external view returns (IHyperdrive.PoolInfo memory) {
        uint256 sharePrice = _pricePerShare();
        uint256 lpTotalSupply = _totalSupply[AssetId._LP_ASSET_ID] +
            _totalSupply[AssetId._WITHDRAWAL_SHARE_ASSET_ID] -
            _withdrawPool.readyToWithdraw;
        uint256 presentValue = sharePrice > 0
            ? HyperdriveMath
                .calculatePresentValue(_getPresentValueParams(sharePrice))
                .mulDown(sharePrice)
            : 0;
        IHyperdrive.PoolInfo memory poolInfo = IHyperdrive.PoolInfo({
            shareReserves: _marketState.shareReserves,
            bondReserves: _marketState.bondReserves,
            sharePrice: sharePrice,
            longsOutstanding: _marketState.longsOutstanding,
            longAverageMaturityTime: _marketState.longAverageMaturityTime,
            shortsOutstanding: _marketState.shortsOutstanding,
            shortAverageMaturityTime: _marketState.shortAverageMaturityTime,
            shortBaseVolume: _marketState.shortBaseVolume,
            lpTotalSupply: lpTotalSupply,
            lpSharePrice: lpTotalSupply == 0
                ? 0
                : presentValue.divDown(lpTotalSupply),
            withdrawalSharesReadyToWithdraw: _withdrawPool.readyToWithdraw,
            withdrawalSharesProceeds: _withdrawPool.proceeds
        });
        _revert(abi.encode(poolInfo));
    }

    /// @notice Gets info about the fees presently accrued by the pool
    /// @return Governance fees denominated in shares yet to be collected
    function getUncollectedGovernanceFees() external view returns (uint256) {
        _revert(abi.encode(_governanceFeesAccrued));
    }

    function getMarketState()
        external
        view
        returns (IHyperdrive.MarketState memory)
    {
        _revert(abi.encode(_marketState));
    }

    /// @notice Allows plugin data libs to provide getters or other complex
    ///         logic instead of the main.
    /// @param _slots The storage slots the caller wants the data from
    /// @return A raw array of loaded data
    function load(
        uint256[] calldata _slots
    ) external view returns (bytes32[] memory) {
        bytes32[] memory loaded = new bytes32[](_slots.length);

        // Iterate on requested loads and then do them
        for (uint256 i = 0; i < _slots.length; i++) {
            uint256 slot = _slots[i];
            bytes32 data;
            assembly ("memory-safe") {
                data := sload(slot)
            }
            loaded[i] = data;
        }

        _revert(abi.encode(loaded));
    }

    /// @notice Returns the average price between the last recorded timestamp looking a user determined
    ///         time into the past
    /// @dev Any integrations should assert the returned value is not equal to the QueryOutOfRange() selector
    /// @param period The gap in our time sample.
    /// @return The average price in that time
    function query(uint256 period) external view returns (uint256) {
        // Load the storage data
        uint256 lastTimestamp = uint256(_oracle.lastTimestamp);
        uint256 head = uint256(_oracle.head);

        OracleData memory currentData = _buffer[head];
        uint256 targetTime = uint256(lastTimestamp) - period;

        // We search for the greatest timestamp before the last, note this is not
        // an efficient search as we expect the buffer to be small.
        uint256 currentIndex = head == 0 ? _buffer.length - 1 : head - 1;
        OracleData memory oldData = OracleData(0, 0);
        while (currentIndex != head) {
            // If the timestamp of the current index has older data than the target
            // this is the newest data which is older than the target so we break
            OracleData storage currentDataCache = _buffer[currentIndex];
            if (uint256(currentDataCache.timestamp) <= targetTime) {
                oldData = currentDataCache;
                break;
            }
            currentIndex = currentIndex == 0
                ? _buffer.length - 1
                : currentIndex - 1;
        }

        if (oldData.timestamp == 0) revert IHyperdrive.QueryOutOfRange();

        // To get twap in period we take the increase in the sum then divide by
        // the amount of time passed
        uint256 deltaSum = uint256(currentData.data) - uint256(oldData.data);
        uint256 deltaTime = uint256(currentData.timestamp) -
            uint256(oldData.timestamp);
        _revert(abi.encode(deltaSum.divDown(deltaTime * 1e18)));
    }
}
