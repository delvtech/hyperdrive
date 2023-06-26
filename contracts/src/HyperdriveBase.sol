// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveStorage } from "./HyperdriveStorage.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { IHyperdrive } from "./interfaces/IHyperdrive.sol";
import { AssetId } from "./libraries/AssetId.sol";
import { Errors } from "./libraries/Errors.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { HyperdriveMath } from "./libraries/HyperdriveMath.sol";
import { SafeCast } from "./libraries/SafeCast.sol";
import { MultiToken } from "./token/MultiToken.sol";

/// @author DELV
/// @title HyperdriveBase
/// @notice The base contract of the Hyperdrive inheritance hierarchy.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveBase is MultiToken, HyperdriveStorage {
    using FixedPointMath for uint256;
    using SafeCast for uint256;

    event Initialize(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount,
        uint256 apr
    );

    event AddLiquidity(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount
    );

    event RemoveLiquidity(
        address indexed provider,
        uint256 lpAmount,
        uint256 baseAmount,
        uint256 withdrawalShareAmount
    );

    event RedeemWithdrawalShares(
        address indexed provider,
        uint256 withdrawalShareAmount,
        uint256 baseAmount
    );

    event OpenLong(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 bondAmount
    );

    event OpenShort(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 bondAmount
    );

    event CloseLong(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 bondAmount
    );

    event CloseShort(
        address indexed trader,
        uint256 indexed assetId,
        uint256 maturityTime,
        uint256 baseAmount,
        uint256 bondAmount
    );

    /// @notice Initializes a Hyperdrive pool.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _dataProvider The address of the data provider.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The address of the factory which is used to deploy
    ///        the ERC20 linker contracts.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _dataProvider,
        bytes32 _linkerCodeHash,
        address _linkerFactory
    )
        MultiToken(_dataProvider, _linkerCodeHash, _linkerFactory)
        HyperdriveStorage(_config)
    {
        // Initialize the oracle.
        for (uint256 i = 0; i < _config.oracleSize; i++) {
            _buffer.push(OracleData(uint32(block.timestamp), 0));
        }
    }

    /// Yield Source ///

    /// @notice A YieldSource dependent check that prevents ether from being
    ///         transferred to Hyperdrive instances that don't accept ether.
    function _checkMessageValue() internal view virtual {
        if (msg.value != 0) {
            revert Errors.NotPayable();
        }
    }

    /// @notice Transfers base from the user and commits it to the yield source.
    /// @param amount The amount of base to deposit.
    /// @param asUnderlying If true the yield source will transfer underlying tokens
    ///                     if false it will transfer the yielding asset directly
    /// @return sharesMinted The shares this deposit creates.
    /// @return sharePrice The share price at time of deposit.
    function _deposit(
        uint256 amount,
        bool asUnderlying
    ) internal virtual returns (uint256 sharesMinted, uint256 sharePrice);

    /// @notice Withdraws shares from the yield source and sends the base
    ///         released to the destination.
    /// @param shares The shares to withdraw from the yield source.
    /// @param destination The recipient of the withdrawal.
    /// @param asUnderlying If true the yield source will transfer underlying tokens
    ///                     if false it will transfer the yielding asset directly
    /// @return amountWithdrawn The amount of base released by the withdrawal.
    function _withdraw(
        uint256 shares,
        address destination,
        bool asUnderlying
    ) internal virtual returns (uint256 amountWithdrawn);

    ///@notice Loads the share price from the yield source
    ///@return sharePrice The current share price.
    function _pricePerShare()
        internal
        view
        virtual
        returns (uint256 sharePrice);

    /// Pause ///

    ///@notice Allows governance to set the ability of an address to pause deposits
    ///@param who The address to change
    ///@param status The new pauser status
    function setPauser(address who, bool status) external {
        if (msg.sender != _governance) revert Errors.Unauthorized();
        _pausers[who] = status;
    }

    ///@notice Allows governance to change governance
    ///@param who The new governance address
    function setGovernance(address who) external {
        if (msg.sender != _governance) revert Errors.Unauthorized();
        _governance = who;
    }

    ///@notice Allows an authorized address to pause this contract
    ///@param status True to pause all deposits and false to unpause them
    function pause(bool status) external {
        if (!_pausers[msg.sender]) revert Errors.Unauthorized();
        _marketState.isPaused = status;
    }

    ///@notice Blocks a function execution if the contract is paused
    modifier isNotPaused() {
        if (_marketState.isPaused) revert Errors.Paused();
        _;
    }

    /// Checkpoint ///

    /// @notice Allows anyone to mint a new checkpoint.
    /// @param _checkpointTime The time of the checkpoint to create.
    function checkpoint(uint256 _checkpointTime) public virtual;

    /// @dev Creates a new checkpoint if necessary.
    /// @param _checkpointTime The time of the checkpoint to create.
    /// @param _sharePrice The current share price.
    /// @return openSharePrice The open share price of the latest checkpoint.
    function _applyCheckpoint(
        uint256 _checkpointTime,
        uint256 _sharePrice
    ) internal virtual returns (uint256 openSharePrice);

    /// @notice This function collects the governance fees accrued by the pool.
    /// @param asUnderlying Indicates if the fees should be paid in underlying or yielding token
    /// @return proceeds The amount of base collected.
    function collectGovernanceFee(
        bool asUnderlying
    ) external returns (uint256 proceeds) {
        // Must have been granted a role
        if (
            !_pausers[msg.sender] &&
            msg.sender != _feeCollector &&
            msg.sender != _governance
        ) revert Errors.Unauthorized();
        uint256 governanceFeesAccrued = _governanceFeesAccrued;
        _governanceFeesAccrued = 0;
        proceeds = _withdraw(
            governanceFeesAccrued,
            _feeCollector,
            asUnderlying
        );
    }

    /// Helpers ///

    /// @dev Calculates the normalized time remaining of a position.
    /// @param _maturityTime The maturity time of the position.
    /// @return timeRemaining The normalized time remaining (in [0, 1]).
    function _calculateTimeRemaining(
        uint256 _maturityTime
    ) internal view returns (uint256 timeRemaining) {
        uint256 latestCheckpoint = _latestCheckpoint();
        timeRemaining = _maturityTime > latestCheckpoint
            ? _maturityTime - latestCheckpoint
            : 0;
        timeRemaining = (timeRemaining).divDown(_positionDuration);
    }

    /// @dev Calculates the normalized time remaining of a position when the
    ///      maturity time is scaled up 18 decimals.
    /// @param _maturityTime The maturity time of the position.
    function _calculateTimeRemainingScaled(
        uint256 _maturityTime
    ) internal view returns (uint256 timeRemaining) {
        uint256 latestCheckpoint = _latestCheckpoint() * FixedPointMath.ONE_18;
        timeRemaining = _maturityTime > latestCheckpoint
            ? _maturityTime - latestCheckpoint
            : 0;
        timeRemaining = (timeRemaining).divDown(
            _positionDuration * FixedPointMath.ONE_18
        );
    }

    /// @dev Gets the most recent checkpoint time.
    /// @return latestCheckpoint The latest checkpoint.
    function _latestCheckpoint()
        internal
        view
        returns (uint256 latestCheckpoint)
    {
        latestCheckpoint =
            block.timestamp -
            (block.timestamp % _checkpointDuration);
    }

    /// @dev Calculates the fees for the flat and curve portion of hyperdrive calcOutGivenIn
    /// @param _amountIn The given amount in, either in terms of shares or bonds.
    /// @param _spotPrice The price without slippage of bonds in terms of shares.
    /// @param _sharePrice The current price of shares in terms of base.
    /// @return totalCurveFee The total curve fee. The fee is in terms of bonds.
    /// @return governanceCurveFee The curve fee that goes to governance. The fee is in terms of bonds.
    function _calculateFeesOutGivenSharesIn(
        uint256 _amountIn,
        uint256 _spotPrice,
        uint256 _sharePrice
    )
        internal
        view
        returns (uint256 totalCurveFee, uint256 governanceCurveFee)
    {
        uint256 rhs = _amountIn
            .mulDown(_curveFee)
            .mulDown(_sharePrice);

        // total curve fee = ((1 / p) - 1) * phi_curve * c * d_z
        totalCurveFee = (FixedPointMath.ONE_18.divDown(_spotPrice)).sub(FixedPointMath.ONE_18)
            .mulDown(rhs);

        // governanceCurveFee = (1 - p) * phi_curve * c * d_z * phi_gov
        governanceCurveFee = (FixedPointMath.ONE_18.sub(_spotPrice))
            .mulDown(rhs)
            .mulDown(_governanceFee); 
    }

    /// @dev Calculates the fees for the flat and curve portion of hyperdrive calcOutGivenIn
    /// @param _amountIn The given amount in, either in terms of shares or bonds.
    /// @param _normalizedTimeRemaining The normalized amount of time until maturity.
    /// @param _spotPrice The price without slippage of bonds in terms of shares.
    /// @param _sharePrice The current price of shares in terms of base.
    /// @return totalCurveFee The curve fee. The fee is in terms of shares.
    /// @return totalFlatFee The flat fee. The fee is in terms of shares.
    /// @return totalGovernanceFee The total fee that goes to governance. The fee is in terms of shares.
    function _calculateFeesOutGivenBondsIn(
        uint256 _amountIn,
        uint256 _normalizedTimeRemaining,
        uint256 _spotPrice,
        uint256 _sharePrice
    )
        internal
        view
        returns (
            uint256 totalCurveFee,
            uint256 totalFlatFee,
            uint256 totalGovernanceFee
        )
    {
        // 'bond' in
        // curve fee = ((1 - p) * phi_curve * d_y * t) / c
        uint256 _pricePart = (FixedPointMath.ONE_18.sub(_spotPrice));
        totalCurveFee = _pricePart
            .mulDown(_curveFee)
            .mulDown(_amountIn)
            .mulDivDown(_normalizedTimeRemaining, _sharePrice);
        // calculate the curve portion of the governance fee
        totalGovernanceFee = totalCurveFee.mulDown(_governanceFee);
        // flat fee = (d_y * (1 - t) * phi_flat) / c
        uint256 flat = _amountIn.mulDivDown(
            FixedPointMath.ONE_18.sub(_normalizedTimeRemaining),
            _sharePrice
        );
        totalFlatFee = (flat.mulDown(_flatFee));
        totalGovernanceFee += totalFlatFee.mulDown(_governanceFee);
    }

    /// @dev Calculates the fees for the curve portion of hyperdrive calcInGivenOut
    /// @param _amountOut The given amount out.
    /// @param _normalizedTimeRemaining The normalized amount of time until maturity.
    /// @param _spotPrice The price without slippage of bonds in terms of shares.
    /// @param _sharePrice The current price of shares in terms of base.
    /// @return totalCurveFee The total curve fee. Fee is in terms of shares.
    /// @return totalFlatFee The total flat fee.  Fee is in terms of shares.
    /// @return governanceCurveFee The curve fee that goes to governance.  Fee is in terms of shares.
    /// @return governanceFlatFee The flat fee that goes to governance.  Fee is in terms of shares.
    function _calculateFeesInGivenBondsOut(
        uint256 _amountOut,
        uint256 _normalizedTimeRemaining,
        uint256 _spotPrice,
        uint256 _sharePrice
    )
        internal
        view
        returns (
            uint256 totalCurveFee,
            uint256 totalFlatFee,
            uint256 governanceCurveFee,
            uint256 governanceFlatFee
        )
    {
        // bonds out
        // curve fee = ((1 - p) * d_y * t * phi_curve)/c
        totalCurveFee = FixedPointMath.ONE_18.sub(_spotPrice);
        totalCurveFee = totalCurveFee
            .mulDown(_curveFee)
            .mulDown(_amountOut)
            .mulDivDown(_normalizedTimeRemaining, _sharePrice);
        // calculate the curve portion of the governance fee
        governanceCurveFee = totalCurveFee.mulDown(_governanceFee);
        // flat fee = (d_y * (1 - t) * phi_flat)/c
        uint256 flat = _amountOut.mulDivDown(
            FixedPointMath.ONE_18.sub(_normalizedTimeRemaining),
            _sharePrice
        );
        totalFlatFee = (flat.mulDown(_flatFee));
        // calculate the flat portion of the governance fee
        governanceFlatFee = totalFlatFee.mulDown(_governanceFee);
    }
}
