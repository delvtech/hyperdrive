// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveBase } from "./HyperdriveBase.sol";
import { IHyperdrive } from "./interfaces/IHyperdrive.sol";
import { IHyperdriveRead } from "./interfaces/IHyperdriveRead.sol";
import { AssetId } from "./libraries/AssetId.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { HyperdriveMath } from "./libraries/HyperdriveMath.sol";
// FIXME: We shouldn't need these.
import { HyperdriveCheckpoint } from "./HyperdriveCheckpoint.sol";
import { HyperdriveLong } from "./HyperdriveLong.sol";
import { HyperdriveShort } from "./HyperdriveShort.sol";

/// @author DELV
/// @title HyperdriveDataProvider
/// @notice The Hyperdrive data provider.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
//
// FIXME: We shouldn't need to inherit `HyperdriveLong`, `HyperdriveShort`, and
// and `HyperdriveCheckpoint` here. Instead of defining `_applyCheckpoint` in
// HyperdriveBase, we could add this as a requirement to the contracts that
// require it with a `IHyperdriveCheckpoint` interface.
abstract contract HyperdriveDataProvider is
    IHyperdriveRead,
    HyperdriveBase,
    HyperdriveLong,
    HyperdriveShort,
    HyperdriveCheckpoint
{
    using FixedPointMath for uint256;

    // solhint-disable no-empty-blocks
    /// @notice Initializes Hyperdrive's data provider.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The address of the factory which is used to deploy
    ///        the ERC20 linker contracts.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        bytes32 _linkerCodeHash,
        address _linkerFactory
    ) HyperdriveBase(_config, _linkerCodeHash, _linkerFactory) {}

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
                    minimumTransactionAmount: _minimumTransactionAmount,
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
            shareAdjustment: _marketState.shareAdjustment,
            bondReserves: _marketState.bondReserves,
            sharePrice: sharePrice,
            longsOutstanding: _marketState.longsOutstanding,
            longAverageMaturityTime: _marketState.longAverageMaturityTime,
            shortsOutstanding: _marketState.shortsOutstanding,
            shortAverageMaturityTime: _marketState.shortAverageMaturityTime,
            lpTotalSupply: lpTotalSupply,
            lpSharePrice: lpTotalSupply == 0
                ? 0
                : presentValue.divDown(lpTotalSupply),
            withdrawalSharesReadyToWithdraw: _withdrawPool.readyToWithdraw,
            withdrawalSharesProceeds: _withdrawPool.proceeds,
            longExposure: _marketState.longExposure
        });
        _revert(abi.encode(poolInfo));
    }

    // FIXME: Comment this.
    function getWithdrawPool()
        external
        view
        returns (IHyperdrive.WithdrawPool memory)
    {
        _revert(
            abi.encode(
                IHyperdrive.WithdrawPool({
                    readyToWithdraw: _withdrawPool.readyToWithdraw,
                    proceeds: _withdrawPool.proceeds
                })
            )
        );
    }

    /// @notice Gets info about the fees presently accrued by the pool
    /// @return Governance fees denominated in shares yet to be collected
    function getUncollectedGovernanceFees() external view returns (uint256) {
        _revert(abi.encode(_governanceFeesAccrued));
    }

    // FIXME: Comment this.
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
        for (uint256 i = 0; i < _slots.length; ) {
            uint256 slot = _slots[i];
            bytes32 data;
            assembly ("memory-safe") {
                data := sload(slot)
            }
            loaded[i] = data;
            unchecked {
                ++i;
            }
        }

        _revert(abi.encode(loaded));
    }

    // FIXME: This should be removed.
    //
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
        _revert(abi.encode(deltaSum / deltaTime));
    }

    /// Token ///

    /// @notice Gets the code hash of the erc20 linker contract.
    /// @return The code hash.
    function linkerCodeHash() external view returns (bytes32) {
        _revert(abi.encode(_linkerCodeHash));
    }

    /// @notice Gets the factory which is used to deploy the linking contracts.
    /// @return The linking factory.
    function factory() external view returns (address) {
        _revert(abi.encode(_factory));
    }

    /// @notice Gets an account's balance of a sub-token.
    /// @param tokenId The sub-token id.
    /// @param account The account.
    /// @return The balance.
    function balanceOf(
        uint256 tokenId,
        address account
    ) external view override returns (uint256) {
        _revert(abi.encode(_balanceOf[tokenId][account]));
    }

    /// @notice Gets the total supply of a sub-token.
    /// @param tokenId The sub-token id.
    /// @return The total supply.
    function totalSupply(
        uint256 tokenId
    ) external view override returns (uint256) {
        _revert(abi.encode(_totalSupply[tokenId]));
    }

    /// @notice Gets the approval status of an operator for an account.
    /// @param account The account.
    /// @param operator The operator.
    /// @return The approval status.
    function isApprovedForAll(
        address account,
        address operator
    ) external view override returns (bool) {
        _revert(abi.encode(_isApprovedForAll[account][operator]));
    }

    /// @notice Gets the approval status of an operator for an account.
    /// @param tokenId The sub-token id.
    /// @param account The account.
    /// @param spender The spender.
    /// @return The approval status.
    function perTokenApprovals(
        uint256 tokenId,
        address account,
        address spender
    ) external view override returns (uint256) {
        _revert(abi.encode(_perTokenApprovals[tokenId][account][spender]));
    }

    /// @notice Gets the name of a sub-token.
    /// @param tokenId The sub-token id.
    /// @return The name.
    function name(
        uint256 tokenId
    ) external pure override returns (string memory) {
        _revert(abi.encode(AssetId.assetIdToName(tokenId)));
    }

    /// @notice Gets the symbol of a sub-token.
    /// @param tokenId The sub-token id.
    /// @return The symbol.
    function symbol(
        uint256 tokenId
    ) external pure override returns (string memory) {
        _revert(abi.encode(AssetId.assetIdToSymbol(tokenId)));
    }

    /// @notice Gets the permitForAll signature nonce for an account.
    /// @param account The account.
    /// @return The signature nonce.
    function nonces(address account) external view override returns (uint256) {
        _revert(abi.encode(_nonces[account]));
    }

    /// Helpers ///

    /// @dev Reverts with the provided bytes. This is useful in getters used
    ///      with the force-revert delegatecall pattern.
    /// @param _bytes The bytes to revert with.
    function _revert(bytes memory _bytes) internal pure {
        revert IHyperdrive.ReturnData(_bytes);
    }
}
