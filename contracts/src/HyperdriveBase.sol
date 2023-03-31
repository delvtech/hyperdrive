// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { MultiToken } from "./MultiToken.sol";
import { AssetId } from "./libraries/AssetId.sol";
import { Errors } from "./libraries/Errors.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { HyperdriveMath } from "./libraries/HyperdriveMath.sol";
import { IHyperdrive } from "./interfaces/IHyperdrive.sol";

/// @author Delve
/// @title HyperdriveBase
/// @notice The base contract of the Hyperdrive inheritance hierarchy.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveBase is MultiToken {
    using FixedPointMath for uint256;
    using SafeCast for uint256;

    /// Tokens ///

    // @notice The base asset.
    IERC20 public immutable baseToken;

    /// Time ///

    // @notice The amount of seconds between share price checkpoints.
    uint256 internal immutable checkpointDuration;

    // @notice The amount of seconds that elapse before a bond can be redeemed.
    uint256 internal immutable positionDuration;

    // @notice A parameter that decreases slippage around a target rate.
    uint256 internal immutable timeStretch;

    /// Market State ///

    // @notice The share price at the time the pool was created.
    uint256 internal immutable initialSharePrice;

    /// @notice The reserves and the buffers. This is the primary state used for
    ///         pricing trades and maintaining solvency.
    IHyperdrive.MarketState internal marketState;

    /// @notice Aggregate values for long positions that are used to enforce
    ///         fairness guarantees.
    IHyperdrive.Aggregates internal longAggregates;

    /// @notice Aggregate values for short positions that are used to enforce
    ///         fairness guarantees.
    IHyperdrive.Aggregates internal shortAggregates;

    /// @notice The state corresponding to the withdraw pool, expressed as a struct.
    IHyperdrive.WithdrawPool internal withdrawPool;

    /// @notice The fee percentages to be applied to the trade equation
    IHyperdrive.Fees internal fees;

    /// @notice Hyperdrive positions are bucketed into checkpoints, which
    ///         allows us to avoid poking in any period that has LP or trading
    ///         activity. The checkpoints contain the starting share price from
    ///         the checkpoint as well as aggregate volume values.
    mapping(uint256 => IHyperdrive.Checkpoint) public checkpoints;

    // TODO: This shouldn't be public.
    //
    // Governance fees that haven't been collected yet denominated in shares.
    uint256 public governanceFeesAccrued;

    // TODO: This shouldn't be public.
    //
    // TODO: Should this be immutable?
    //
    // The address that receives governance fees.
    address public governance;

    /// @notice Initializes a Hyperdrive pool.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The address of the factory which is used to deploy
    ///        the ERC20 linker contracts.
    /// @param _baseToken The base token contract.
    /// @param _initialSharePrice The initial share price.
    /// @param _checkpointsPerTerm The number of checkpoints that elapses before
    ///        bonds can be redeemed one-to-one for base.
    /// @param _checkpointDuration The time in seconds between share price
    ///        checkpoints. Position duration must be a multiple of checkpoint
    ///        duration.
    /// @param _timeStretch The time stretch of the pool.
    /// @param _fees The fees to apply to trades.
    /// @param _governance The address that receives governance fees.
    constructor(
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        IERC20 _baseToken,
        uint256 _initialSharePrice,
        uint256 _checkpointsPerTerm,
        uint256 _checkpointDuration,
        uint256 _timeStretch,
        IHyperdrive.Fees memory _fees,
        address _governance
    ) MultiToken(_linkerCodeHash, _linkerFactory) {
        // Initialize the base token address.
        baseToken = _baseToken;

        // Initialize the time configurations. There must be at least one
        // checkpoint per term to avoid having a position duration of zero.
        if (_checkpointsPerTerm == 0) {
            revert Errors.InvalidCheckpointsPerTerm();
        }
        positionDuration = _checkpointsPerTerm * _checkpointDuration;
        checkpointDuration = _checkpointDuration;
        timeStretch = _timeStretch;
        initialSharePrice = _initialSharePrice;
        fees = _fees;
        governance = _governance;
    }

    /// Yield Source ///

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
    /// @return sharePrice The share price on withdraw.
    function _withdraw(
        uint256 shares,
        address destination,
        bool asUnderlying
    ) internal virtual returns (uint256 amountWithdrawn, uint256 sharePrice);

    ///@notice Loads the share price from the yield source
    ///@return sharePrice The current share price.
    function _pricePerShare()
        internal
        view
        virtual
        returns (uint256 sharePrice);

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
    /// @return proceeds The amount of base collected.
    function collectGovernanceFee() external returns (uint256 proceeds) {
        // TODO: We should make an immutable asUnderlying parameter
        (proceeds, ) = _withdraw(governanceFeesAccrued, governance, true);
        governanceFeesAccrued = 0;
    }

    /// Getters ///

    // TODO: The fee parameters aren't immutable right now, but arguably they
    //       should be.
    //
    /// @notice Gets the pool's configuration parameters.
    /// @dev These parameters are immutable, so this should only need to be
    ///      called once.
    /// @return The PoolConfig struct.
    function getPoolConfig()
        external
        view
        returns (IHyperdrive.PoolConfig memory)
    {
        return
            IHyperdrive.PoolConfig({
                initialSharePrice: initialSharePrice,
                positionDuration: positionDuration,
                checkpointDuration: checkpointDuration,
                timeStretch: timeStretch,
                flatFee: fees.flat,
                curveFee: fees.curve,
                governanceFee: fees.governance
            });
    }

    /// @notice Gets info about the pool's reserves and other state that is
    ///         important to evaluate potential trades.
    /// @return The PoolInfo struct.
    function getPoolInfo() external view returns (IHyperdrive.PoolInfo memory) {
        return
            IHyperdrive.PoolInfo({
                shareReserves: marketState.shareReserves,
                bondReserves: marketState.bondReserves,
                lpTotalSupply: totalSupply[AssetId._LP_ASSET_ID],
                sharePrice: _pricePerShare(),
                longsOutstanding: marketState.longsOutstanding,
                longAverageMaturityTime: longAggregates.averageMaturityTime,
                longBaseVolume: longAggregates.baseVolume,
                shortsOutstanding: marketState.shortsOutstanding,
                shortAverageMaturityTime: shortAggregates.averageMaturityTime,
                shortBaseVolume: shortAggregates.baseVolume,
                withdrawalSharesReadyToWithdraw: withdrawPool
                    .withdrawalSharesReadyToWithdraw,
                capital: withdrawPool.capital,
                interest: withdrawPool.interest
            });
    }

    /// Helpers ///

    /// @dev Calculates the normalized time remaining of a position.
    /// @param _maturityTime The maturity time of the position.
    /// @return timeRemaining The normalized time remaining (in [0, 1]).
    function _calculateTimeRemaining(
        uint256 _maturityTime
    ) internal view returns (uint256 timeRemaining) {
        timeRemaining = _maturityTime > block.timestamp
            ? _maturityTime - block.timestamp
            : 0;
        timeRemaining = (timeRemaining).divDown(positionDuration);
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
            (block.timestamp % checkpointDuration);
    }

    // TODO: Consider combining this with the trading functions.
    //
    /// @dev Calculates the fees for the flat and curve portion of hyperdrive calcOutGivenIn
    /// @param _amountIn The given amount in, either in terms of shares or bonds.
    /// @param _amountOut The amount of the asset that is received before fees.
    /// @param _normalizedTimeRemaining The normalized amount of time until maturity.
    /// @param _spotPrice The price without slippage of bonds in terms of shares.
    /// @param _sharePrice The current price of shares in terms of base.
    /// @return totalCurveFee The total curve fee. The fee is in terms of bonds.
    /// @return totalFlatFee The total flat fee. The fee is in terms of bonds.
    /// @return governanceCurveFee The curve fee that goes to governance. The fee is in terms of bonds.
    /// @return governanceFlatFee The flat fee that goes to governance. The fee is in terms of bonds.
    function _calculateFeesOutGivenSharesIn(
        uint256 _amountIn,
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
        // curve fee = ((1 / p) - 1) * phi_curve * c * d_z * t
        totalCurveFee = (FixedPointMath.ONE_18.divDown(_spotPrice)).sub(
            FixedPointMath.ONE_18
        );
        totalCurveFee = totalCurveFee
            .mulDown(fees.curve)
            .mulDown(_sharePrice)
            .mulDown(_amountIn)
            .mulDown(_normalizedTimeRemaining);
        // governanceCurveFee = d_z * (curve_fee / d_y) * c * phi_gov
        governanceCurveFee = _amountIn
            .mulDivDown(totalCurveFee, _amountOut)
            .mulDown(_sharePrice)
            .mulDown(fees.governance);
        // flat fee = c * d_z * (1 - t) * phi_flat
        uint256 flat = _amountIn.mulDown(
            FixedPointMath.ONE_18.sub(_normalizedTimeRemaining)
        );
        totalFlatFee = flat.mulDown(_sharePrice).mulDown(fees.flat);
        // calculate the flat portion of the governance fee
        governanceFlatFee = totalFlatFee.mulDown(fees.governance);
    }

    // TODO: Consider combining this with the trading functions.
    //
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
            .mulDown(fees.curve)
            .mulDown(_amountIn)
            .mulDivDown(_normalizedTimeRemaining, _sharePrice);
        // calculate the curve portion of the governance fee
        totalGovernanceFee = totalCurveFee.mulDown(fees.governance);
        // flat fee = (d_y * (1 - t) * phi_flat) / c
        uint256 flat = _amountIn.mulDivDown(
            FixedPointMath.ONE_18.sub(_normalizedTimeRemaining),
            _sharePrice
        );
        totalFlatFee = (flat.mulDown(fees.flat));
        totalGovernanceFee += totalFlatFee.mulDown(fees.governance);
    }

    // TODO: Consider combining this with the trading functions.
    //
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
            .mulDown(fees.curve)
            .mulDown(_amountOut)
            .mulDivDown(_normalizedTimeRemaining, _sharePrice);
        // calculate the curve portion of the governance fee
        governanceCurveFee = totalCurveFee.mulDown(fees.governance);
        // flat fee = (d_y * (1 - t) * phi_flat)/c
        uint256 flat = _amountOut.mulDivDown(
            FixedPointMath.ONE_18.sub(_normalizedTimeRemaining),
            _sharePrice
        );
        totalFlatFee = (flat.mulDown(fees.flat));
        // calculate the flat portion of the governance fee
        governanceFlatFee = totalFlatFee.mulDown(fees.governance);
    }
}
