// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AssetId } from "contracts/libraries/AssetId.sol";
import { Errors } from "contracts/libraries/Errors.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/libraries/HyperdriveMath.sol";
import { MultiToken } from "contracts/MultiToken.sol";
import { IHyperdrive } from "contracts/interfaces/IHyperdrive.sol";

/// @author Delve
/// @title Hyperdrive
/// @notice A fixed-rate AMM that mints bonds on demand for longs and shorts.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract Hyperdrive is MultiToken, IHyperdrive {
    using FixedPointMath for uint256;

    /// Tokens ///

    // @notice The base asset.
    IERC20 public immutable baseToken;

    /// Time ///

    // @notice The amount of seconds between share price checkpoints.
    uint256 public immutable checkpointDuration;

    // @notice The amount of seconds that elapse before a bond can be redeemed.
    uint256 public immutable positionDuration;

    // @notice A parameter that decreases slippage around a target rate.
    uint256 public immutable timeStretch;

    /// Market state ///

    // @notice The share price at the time the pool was created.
    uint256 public immutable initialSharePrice;

    /// @notice Checkpoints of historical share prices.
    mapping(uint256 => uint256) public checkpoints;

    /// @notice The share reserves. The share reserves multiplied by the share
    ///         price give the base reserves, so shares are a mechanism of
    ///         ensuring that interest is properly awarded over time.
    uint256 public shareReserves;

    /// @notice The bond reserves. In Hyperdrive, the bond reserves aren't
    ///         backed by pre-minted bonds and are instead used as a virtual
    ///         value that ensures that the spot rate changes according to the
    ///         laws of supply and demand.
    uint256 public bondReserves;

    /// @notice The amount of longs that are still open.
    uint256 public longsOutstanding;

    /// @notice The amount of shorts that are still open.
    uint256 public shortsOutstanding;

    /// @notice The average maturity time of long positions.
    uint256 public longAverageMaturityTime;

    /// @notice The average maturity time of short positions.
    uint256 public shortAverageMaturityTime;

    /// @notice The amount of long withdrawal shares that haven't been paid out.
    uint256 public longWithdrawalSharesOutstanding;

    /// @notice The amount of short withdrawal shares that haven't been paid out.
    uint256 public shortWithdrawalSharesOutstanding;

    /// @notice The proceeds that have accrued to the long withdrawal shares.
    uint256 public longWithdrawalShareProceeds;

    /// @notice The proceeds that have accrued to the short withdrawal shares.
    uint256 public shortWithdrawalShareProceeds;

    // TODO: Should this be immutable?
    //
    /// @notice The fee paramater to apply to the curve portion of the
    ///         hyperdrive trade equation.
    uint256 public curveFee;

    // TODO: Should this be immutable?
    //
    /// @notice The fee paramater to apply to the flat portion of the hyperdrive
    ///         trade equation.
    uint256 public flatFee;

    /// @notice Initializes a Hyperdrive pool.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The address of the factory which is used to deploy
    ///        the ERC20 linker contracts.
    /// @param _baseToken The base token contract.
    /// @param _initialSharePrice The initial share price.
    /// @param _checkpointsPerTerm The number of checkpoints that elaspes before
    ///        bonds can be redeemed one-to-one for base.
    /// @param _checkpointDuration The time in seconds between share price
    ///        checkpoints. Position duration must be a multiple of checkpoint
    ///        duration.
    /// @param _timeStretch The time stretch of the pool.
    /// @param _curveFee The fee parameter for the curve portion of the hyperdrive trade equation.
    /// @param _flatFee The fee parameter for the flat portion of the hyperdrive trade equation.
    constructor(
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        IERC20 _baseToken,
        uint256 _initialSharePrice,
        uint256 _checkpointsPerTerm,
        uint256 _checkpointDuration,
        uint256 _timeStretch,
        uint256 _curveFee,
        uint256 _flatFee
    ) MultiToken(_linkerCodeHash, _linkerFactory) {
        // Initialize the base token address.
        baseToken = _baseToken;

        // Initialize the time configurations.
        positionDuration = _checkpointsPerTerm * _checkpointDuration;
        checkpointDuration = _checkpointDuration;
        timeStretch = _timeStretch;

        initialSharePrice = _initialSharePrice;

        curveFee = _curveFee;
        flatFee = _flatFee;
    }

    /// Yield Source ///

    /// @notice Transfers base from the user and commits it to the yield source.
    /// @param amount The amount of base to deposit.
    /// @return sharesMinted The shares this deposit creates.
    /// @return sharePrice The share price at time of deposit.
    function deposit(
        uint256 amount
    ) internal virtual returns (uint256 sharesMinted, uint256 sharePrice);

    /// @notice Withdraws shares from the yield source and sends the base
    ///         released to the destination.
    /// @param shares The shares to withdraw from the yieldsource.
    /// @param destination The recipient of the withdrawal.
    /// @return amountWithdrawn The amount of base released by the withdrawal.
    /// @return sharePrice The share price on withdraw.
    function withdraw(
        uint256 shares,
        address destination
    ) internal virtual returns (uint256 amountWithdrawn, uint256 sharePrice);

    ///@notice Loads the share price from the yield source
    ///@return sharePrice The current share price.
    function pricePerShare() internal view virtual returns (uint256 sharePrice);

    /// LP ///

    /// @notice Allows the first LP to initialize the market with a target APR.
    /// @param _contribution The amount of base to supply.
    /// @param _apr The target APR.
    function initialize(uint256 _contribution, uint256 _apr) external {
        // Ensure that the pool hasn't been initialized yet.
        if (shareReserves > 0 || bondReserves > 0) {
            revert Errors.PoolAlreadyInitialized();
        }

        // Deposit for the user, this transfers from them.
        (uint256 shares, uint256 sharePrice) = deposit(_contribution);

        // Create an initial checkpoint.
        _applyCheckpoint(_latestCheckpoint(), sharePrice);

        // Update the reserves. The bond reserves are calculated so that the
        // pool is initialized with the target APR.
        shareReserves = shares;
        bondReserves = HyperdriveMath.calculateInitialBondReserves(
            shares,
            sharePrice,
            initialSharePrice,
            _apr,
            positionDuration,
            timeStretch
        );

        // Mint LP shares to the initializer.
        // TODO - Should we index the lp share and virtual reserve to shares or to underlying?
        //        I think in the case where price per share < 1 there may be a problem.
        _mint(
            AssetId._LP_ASSET_ID,
            msg.sender,
            sharePrice.mulDown(shares).add(bondReserves)
        );
    }

    // TODO: Add slippage protection.
    //
    /// @notice Allows LPs to supply liquidity for LP shares.
    /// @param _contribution The amount of base to supply.
    /// @param _minOutput The minimum number of LP tokens the user should receive
    /// @param _destination The address which will hold the LP shares
    /// @return lpShares The number of LP tokens created
    function addLiquidity(
        uint256 _contribution,
        uint256 _minOutput,
        address _destination
    ) external returns (uint256 lpShares) {
        if (_contribution == 0) {
            revert Errors.ZeroAmount();
        }

        // Deposit for the user, this call also transfers from them
        (uint256 shares, uint256 sharePrice) = deposit(_contribution);

        // Perform a checkpoint.
        _applyCheckpoint(_latestCheckpoint(), sharePrice);

        // Calculate the pool's APR prior to updating the share reserves so that
        // we can compute the bond reserves update.
        uint256 apr = HyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            totalSupply[AssetId._LP_ASSET_ID],
            initialSharePrice,
            positionDuration,
            timeStretch
        );

        // Calculate the amount of LP shares that the supplier should receive.
        lpShares = HyperdriveMath.calculateLpSharesOutForSharesIn(
            shares,
            shareReserves,
            totalSupply[AssetId._LP_ASSET_ID],
            longsOutstanding,
            shortsOutstanding,
            sharePrice
        );

        // Enforce min user outputs
        if (_minOutput > lpShares) revert Errors.OutputLimit();

        // Update the reserves.
        shareReserves += shares;
        bondReserves = HyperdriveMath.calculateBondReserves(
            shareReserves,
            totalSupply[AssetId._LP_ASSET_ID] + lpShares,
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );

        // Mint LP shares to the supplier.
        _mint(AssetId._LP_ASSET_ID, _destination, lpShares);
    }

    // TODO: Consider if some MEV protection is necessary for the LP.
    //
    /// @notice Allows an LP to burn shares and withdraw from the pool.
    /// @param _shares The LP shares to burn.
    /// @param _minOutput The minium amount of the base token to receive. Note - this
    ///                   value is likely to be less than the amount LP shares are worth.
    ///                   The remainder is in short and long withdraw shares which are hard
    ///                   to game the value of.
    /// @param _destination The address which will receive the withdraw proceeds
    /// @return Returns the base out, the lond withdraw shares out and the short withdraw
    ///         shares out.
    function removeLiquidity(
        uint256 _shares,
        uint256 _minOutput,
        address _destination
    ) external returns (uint256, uint256, uint256) {
        if (_shares == 0) {
            revert Errors.ZeroAmount();
        }

        // Perform a checkpoint.
        uint256 sharePrice = pricePerShare();
        _applyCheckpoint(_latestCheckpoint(), sharePrice);

        // Calculate the pool's APR prior to updating the share reserves and LP
        // total supply so that we can compute the bond reserves update.
        uint256 apr = HyperdriveMath.calculateAPRFromReserves(
            shareReserves,
            bondReserves,
            totalSupply[AssetId._LP_ASSET_ID],
            initialSharePrice,
            positionDuration,
            timeStretch
        );

        // Calculate the withdrawal proceeds of the LP. This includes the base,
        // long withdrawal shares, and short withdrawal shares that the LP
        // receives.
        (
            uint256 shareProceeds,
            uint256 longWithdrawalShares,
            uint256 shortWithdrawalShares
        ) = HyperdriveMath.calculateOutForLpSharesIn(
                _shares,
                shareReserves,
                totalSupply[AssetId._LP_ASSET_ID],
                longsOutstanding,
                shortsOutstanding,
                sharePrice
            );

        // Burn the LP shares.
        _burn(AssetId._LP_ASSET_ID, msg.sender, _shares);

        // Update the reserves.
        shareReserves -= shareProceeds;
        bondReserves = HyperdriveMath.calculateBondReserves(
            shareReserves,
            totalSupply[AssetId._LP_ASSET_ID],
            initialSharePrice,
            apr,
            positionDuration,
            timeStretch
        );

        // TODO: Update this when we implement tranches.
        //
        // Mint the long and short withdrawal tokens.
        _mint(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.LongWithdrawalShare, 0),
            _destination,
            longWithdrawalShares
        );
        longWithdrawalSharesOutstanding += longWithdrawalShares;
        _mint(
            AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.ShortWithdrawalShare,
                0
            ),
            _destination,
            shortWithdrawalShares
        );
        shortWithdrawalSharesOutstanding += shortWithdrawalShares;

        // Withdraw the shares from the yield source
        // TODO - Good destination support.
        (uint256 baseOutput, ) = withdraw(shareProceeds, _destination);
        // Enforce min user outputs
        if (_minOutput > baseOutput) revert Errors.OutputLimit();
        return (baseOutput, longWithdrawalShares, shortWithdrawalShares);
    }

    /// @notice Redeems long and short withdrawal shares.
    /// @param _longWithdrawalShares The long withdrawal shares to redeem.
    /// @param _shortWithdrawalShares The short withdrawal shares to redeem.
    /// @param _minOutput The minimum amount of base the LP expects to receive.
    /// @param _destination The address which receive the withdraw proceeds
    /// @return _proceeds The amount of base the LP received.
    function redeemWithdrawalShares(
        uint256 _longWithdrawalShares,
        uint256 _shortWithdrawalShares,
        uint256 _minOutput,
        address _destination
    ) external returns (uint256 _proceeds) {
        uint256 baseProceeds = 0;

        // Perform a checkpoint.
        uint256 sharePrice = pricePerShare();
        _applyCheckpoint(_latestCheckpoint(), sharePrice);

        // Redeem the long withdrawal shares.
        uint256 proceeds = _applyWithdrawalShareRedemption(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.LongWithdrawalShare, 0),
            _longWithdrawalShares,
            longWithdrawalSharesOutstanding,
            longWithdrawalShareProceeds
        );

        // Redeem the short withdrawal shares.
        proceeds += _applyWithdrawalShareRedemption(
            AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.ShortWithdrawalShare,
                0
            ),
            _shortWithdrawalShares,
            shortWithdrawalSharesOutstanding,
            shortWithdrawalShareProceeds
        );

        // Withdraw the funds released by redeeming the withdrawal shares.
        // TODO: Better destination support.
        uint256 shareProceeds = baseProceeds.divDown(sharePrice);
        (_proceeds, ) = withdraw(shareProceeds, _destination);

        // Enforce min user outputs
        if (_minOutput > _proceeds) revert Errors.OutputLimit();
    }

    /// Long ///

    /// @notice Opens a long position.
    /// @param _baseAmount The amount of base to use when trading.
    /// @param _minOutput The minium number of bonds to receive.
    /// @param _destination The address which will receive the bonds
    /// @return The number of bonds the user received
    function openLong(
        uint256 _baseAmount,
        uint256 _minOutput,
        address _destination
    ) external returns (uint256) {
        if (_baseAmount == 0) {
            revert Errors.ZeroAmount();
        }

        // Deposit the user's base.
        (uint256 shares, uint256 sharePrice) = deposit(_baseAmount);

        // Perform a checkpoint.
        uint256 latestCheckpoint = _latestCheckpoint();
        _applyCheckpoint(latestCheckpoint, sharePrice);

        // Calculate the pool and user deltas using the trading function. We
        // backdate the bonds purchased to the beginning of the checkpoint. We
        // reduce the purchasing power of the longs by the amount of interest
        // earned in shares.
        uint256 maturityTime = latestCheckpoint + positionDuration;
        uint256 timeRemaining = _calculateTimeRemaining(maturityTime);
        (, uint256 poolBondDelta, uint256 bondProceeds) = HyperdriveMath
            .calculateOutGivenIn(
                shareReserves,
                bondReserves,
                totalSupply[AssetId._LP_ASSET_ID],
                shares, // amountIn
                timeRemaining,
                timeStretch,
                sharePrice,
                initialSharePrice,
                true // isBaseIn
            );

        uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
            shareReserves,
            bondReserves,
            totalSupply[AssetId._LP_ASSET_ID],
            initialSharePrice,
            // normalizedTimeRemaining, when opening a position, the full time is remaining
            FixedPointMath.ONE_18,
            timeStretch
        );
        (uint256 _curveFee, uint256 _flatFee) = HyperdriveMath
            .calculateFeesOutGivenIn(
                shares, // amountIn
                // normalizedTimeRemaining, when opening a position, the full time is remaining
                FixedPointMath.ONE_18,
                spotPrice,
                sharePrice,
                curveFee,
                flatFee,
                true // isBaseIn
            );
        // This is a base in / bond out operation where the in is given, so we subtract the fee
        // amount from the output.
        bondProceeds -= _curveFee - _flatFee;
        poolBondDelta -= _curveFee;

        // Enforce min user outputs
        if (_minOutput > bondProceeds) revert Errors.OutputLimit();

        // Update the average maturity time of long positions.
        longAverageMaturityTime = _calculateAverageMaturityTime(
            longsOutstanding,
            bondProceeds,
            longAverageMaturityTime,
            maturityTime,
            true
        );

        // Apply the trading deltas to the reserves and update the amount of
        // longs outstanding.
        shareReserves += shares;
        bondReserves -= poolBondDelta;
        longsOutstanding += bondProceeds;

        // TODO: We should fuzz test this and other trading functions to ensure
        // that the APR never goes below zero. If it does, we may need to
        // enforce additional invariants.
        //
        // Since the base buffer may have increased relative to the base
        // reserves and the bond reserves decreased, we must ensure that the
        // base reserves are greater than the longsOutstanding.
        if (sharePrice.mulDown(shareReserves) < longsOutstanding) {
            revert Errors.BaseBufferExceedsShareReserves();
        }

        // Mint the bonds to the trader with an ID of the maturity time.
        _mint(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            _destination,
            bondProceeds
        );
        return (bondProceeds);
    }

    /// @notice Closes a long position with a specified maturity time.
    /// @param _maturityTime The maturity time of the short.
    /// @param _bondAmount The amount of longs to close.
    /// @param _minOutput The minimum base the user should receive from this trade
    /// @param _destination The address which will receive the proceeds of this sale
    /// @return The amount of underlying the user receives.
    function closeLong(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        address _destination
    ) external returns (uint256) {
        if (_bondAmount == 0) {
            revert Errors.ZeroAmount();
        }

        // Perform a checkpoint.
        uint256 sharePrice = pricePerShare();
        _applyCheckpoint(_latestCheckpoint(), sharePrice);

        {
            // Burn the longs that are being closed.
            uint256 assetId = AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.Long,
                _maturityTime
            );
            _burn(assetId, msg.sender, _bondAmount);
        }

        // Calculate the pool and user deltas using the trading function.
        uint256 timeRemaining = _calculateTimeRemaining(_maturityTime);
        (, uint256 poolBondDelta, uint256 shareProceeds) = HyperdriveMath
            .calculateOutGivenIn(
                shareReserves,
                bondReserves,
                totalSupply[AssetId._LP_ASSET_ID],
                _bondAmount,
                timeRemaining,
                timeStretch,
                sharePrice,
                initialSharePrice,
                false
            );
        uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
            shareReserves,
            bondReserves,
            totalSupply[AssetId._LP_ASSET_ID],
            initialSharePrice,
            // normalizedTimeRemaining, when opening a position, the full time is remaining
            FixedPointMath.ONE_18,
            timeStretch
        );
        {
            (uint256 _curveFee, uint256 _flatFee) = HyperdriveMath
                .calculateFeesOutGivenIn(
                    _bondAmount, // amountIn
                    // normalizedTimeRemaining, when opening a position, the full time is remaining
                    FixedPointMath.ONE_18,
                    spotPrice,
                    sharePrice,
                    curveFee,
                    flatFee,
                    false // isBaseIn
                );
            // This is a bond in / base out where the bonds are fixed, so we subtract from the base
            // out.
            shareProceeds -= _curveFee + _flatFee;
        }

        // If the position hasn't matured, apply the accounting updates that
        // result from closing the long to the reserves and pay out the
        // withdrawal pool if necessary. If the position has reached maturity,
        // create a checkpoint at the maturity time if necessary.
        if (block.timestamp < _maturityTime) {
            _applyCloseLong(
                _bondAmount,
                poolBondDelta,
                shareProceeds,
                sharePrice,
                _maturityTime
            );
        } else {
            // Perform a checkpoint for the long's maturity time. This ensures
            // that the matured position has been applied to the reserves.
            checkpoint(_maturityTime);
        }

        // Withdraw the profit to the trader.
        (uint256 baseProceeds, ) = withdraw(shareProceeds, _destination);

        // Enforce min user outputs
        if (_minOutput > baseProceeds) revert Errors.OutputLimit();

        return (baseProceeds);
    }

    /// Short ///

    /// @notice Opens a short position.
    /// @param _bondAmount The amount of bonds to short.
    /// @param _maxDeposit The most the user expects to deposit for this trade
    /// @param _destination The address which gets credited with share tokens
    /// @return The amount the user deposited for this trade
    function openShort(
        uint256 _bondAmount,
        uint256 _maxDeposit,
        address _destination
    ) external returns (uint256) {
        if (_bondAmount == 0) {
            revert Errors.ZeroAmount();
        }

        // Perform a checkpoint and compute the amount of interest the short
        // would have received if they opened at the beginning of the checkpoint.
        // Since the short will receive interest from the beginning of the
        // checkpoint, they will receive this backdated interest back at closing.
        uint256 sharePrice = pricePerShare();
        uint256 latestCheckpoint = _latestCheckpoint();
        uint256 openSharePrice = _applyCheckpoint(latestCheckpoint, sharePrice);

        // Calculate the pool and user deltas using the trading function. We
        // backdate the bonds sold to the beginning of the checkpoint.
        uint256 maturityTime = latestCheckpoint + positionDuration;
        uint256 timeRemaining = _calculateTimeRemaining(maturityTime);
        (uint256 poolShareDelta, , uint256 shareProceeds) = HyperdriveMath
            .calculateOutGivenIn(
                shareReserves,
                bondReserves,
                totalSupply[AssetId._LP_ASSET_ID],
                _bondAmount,
                timeRemaining,
                timeStretch,
                sharePrice,
                initialSharePrice,
                false
            );

        // Take custody of the maximum amount the trader can lose on the short
        // and the extra interest the short will receive at closing (since the
        // proceeds of the trades are calculated using the checkpoint's open
        // share price). This extra interest can be calculated as:
        //
        // interest = (c_1 - c_0) * (dy / c_0)
        //          = (c_1 / c_0 - 1) * dy
        uint256 userDeposit;
        {
            uint256 owedInterest = (sharePrice.divDown(openSharePrice) -
                FixedPointMath.ONE_18).mulDown(_bondAmount);
            uint256 baseProceeds = shareProceeds.mulDown(sharePrice);
            userDeposit = (_bondAmount - baseProceeds) + owedInterest;
            // Enforce min user outputs
            if (_maxDeposit < userDeposit) revert Errors.OutputLimit();
            deposit(userDeposit); // max_loss + interest
        }

        // Update the average maturity time of long positions.
        shortAverageMaturityTime = _calculateAverageMaturityTime(
            shortsOutstanding,
            _bondAmount,
            shortAverageMaturityTime,
            maturityTime,
            true
        );

        // Apply the trading deltas to the reserves and increase the bond buffer
        // by the amount of bonds that were shorted. We don't need to add the
        // margin or pre-paid interest to the reserves because of the way that
        // the close short accounting works.
        shareReserves -= poolShareDelta;
        bondReserves += _bondAmount;
        shortsOutstanding += _bondAmount;

        // Since the share reserves are reduced, we need to verify that the base
        // reserves are greater than or equal to the amount of longs outstanding.
        if (sharePrice.mulDown(shareReserves) < longsOutstanding) {
            revert Errors.BaseBufferExceedsShareReserves();
        }

        // Mint the short tokens to the trader. The ID is a concatenation of the
        // current share price and the maturity time of the shorts.
        _mint(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, maturityTime),
            _destination,
            _bondAmount
        );

        return (userDeposit);
    }

    /// @notice Closes a short position with a specified maturity time.
    /// @param _maturityTime The maturity time of the short.
    /// @param _bondAmount The amount of shorts to close.
    /// @param _minOutput The minimum output of this trade.
    /// @param _destination The address which gets the proceeds from closing this short
    /// @return The amount of base tokens produced by closing this short
    function closeShort(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        address _destination
    ) external returns (uint256) {
        if (_bondAmount == 0) {
            revert Errors.ZeroAmount();
        }

        // Perform a checkpoint.
        uint256 sharePrice = pricePerShare();
        _applyCheckpoint(_latestCheckpoint(), sharePrice);

        // Burn the shorts that are being closed.
        uint256 assetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Short,
            _maturityTime
        );
        _burn(assetId, msg.sender, _bondAmount);

        // Calculate the pool and user deltas using the trading function.
        uint256 timeRemaining = _calculateTimeRemaining(_maturityTime);
        (, uint256 poolBondDelta, uint256 sharePayment) = HyperdriveMath
            .calculateSharesInGivenBondsOut(
                shareReserves,
                bondReserves,
                totalSupply[AssetId._LP_ASSET_ID],
                _bondAmount,
                timeRemaining,
                timeStretch,
                sharePrice,
                initialSharePrice
            );

        // If the position hasn't matured, apply the accounting updates that
        // result from closing the short to the reserves and pay out the
        // withdrawal pool if necessary. If the position has reached maturity,
        // create a checkpoint at the maturity time if necessary.
        if (block.timestamp < _maturityTime) {
            _applyCloseShort(
                _bondAmount,
                poolBondDelta,
                sharePayment,
                sharePrice,
                _maturityTime
            );
        } else {
            // Perform a checkpoint for the short's maturity time. This ensures
            // that the matured position has been applied to the reserves.
            checkpoint(_maturityTime);
        }

        // Withdraw the profit to the trader. This includes the proceeds from
        // the short sale as well as the variable interest that was collected
        // on the face value of the bonds. The math for the short's proceeds in
        // base is given by:
        //
        // proceeds = dy - c_1 * dz + (c_1 - c_0) * (dy / c_0)
        //          = dy - c_1 * dz + (c_1 / c_0) * dy - dy
        //          = (c_1 / c_0) * dy - c_1 * dz
        //          = c_1 * (dy / c_0 - dz)
        //
        // To convert to proceeds in shares, we simply divide by the current
        // share price:
        //
        // shareProceeds = (c_1 * (dy / c_0 - dz)) / c
        uint256 openSharePrice = checkpoints[_maturityTime - positionDuration];
        uint256 closeSharePrice = sharePrice;
        if (_maturityTime <= block.timestamp) {
            closeSharePrice = checkpoints[_maturityTime];
        }
        _bondAmount = _bondAmount.divDown(openSharePrice).sub(sharePayment);
        uint256 shortProceeds = closeSharePrice.mulDown(_bondAmount).divDown(
            sharePrice
        );
        // TODO - Better destination support
        (uint256 baseProceeds, ) = withdraw(shortProceeds, _destination);

        // Enforce min user outputs
        if (baseProceeds < _minOutput) revert Errors.OutputLimit();
        return (baseProceeds);
    }

    /// Checkpoint ///

    /// @notice Allows anyone to mint a new checkpoint.
    /// @param _checkpointTime The time of the checkpoint to create.
    function checkpoint(uint256 _checkpointTime) public {
        // If the checkpoint has already been set, return early.
        if (checkpoints[_checkpointTime] != 0) {
            return;
        }

        // If the checkpoint time isn't divisible by the checkpoint duration
        // or is in the future, it's an invalid checkpoint and we should
        // revert.
        uint256 latestCheckpoint = _latestCheckpoint();
        if (
            _checkpointTime % checkpointDuration != 0 ||
            latestCheckpoint < _checkpointTime
        ) {
            revert Errors.InvalidCheckpointTime();
        }

        // If the checkpoint time is the latest checkpoint, we use the current
        // share price. Otherwise, we use a linear search to find the closest
        // share price and use that to perform the checkpoint.
        if (_checkpointTime == latestCheckpoint) {
            _applyCheckpoint(latestCheckpoint, pricePerShare());
        } else {
            for (uint256 time = _checkpointTime; ; time += checkpointDuration) {
                uint256 closestSharePrice = checkpoints[time];
                if (time == latestCheckpoint) {
                    closestSharePrice = pricePerShare();
                }
                if (closestSharePrice != 0) {
                    _applyCheckpoint(_checkpointTime, closestSharePrice);
                }
            }
        }
    }

    /// Getters ///

    /// @notice Gets info about the pool's reserves and other state that is
    ///         important to evaluate potential trades.
    /// @return shareReserves_ The share reserves.
    /// @return bondReserves_ The bond reserves.
    /// @return lpTotalSupply The total supply of LP shares.
    /// @return sharePrice The share price.
    /// @return longsOutstanding_ The longs that haven't been closed.
    /// @return shortsOutstanding_ The shorts that haven't been closed.
    function getPoolInfo()
        external
        view
        returns (
            uint256 shareReserves_,
            uint256 bondReserves_,
            uint256 lpTotalSupply,
            uint256 sharePrice,
            uint256 longsOutstanding_,
            uint256 shortsOutstanding_
        )
    {
        return (
            shareReserves,
            bondReserves,
            totalSupply[AssetId._LP_ASSET_ID],
            pricePerShare(),
            longsOutstanding,
            shortsOutstanding
        );
    }

    /// Helpers ///

    /// @dev Applies the trading deltas from a closed long to the reserves and
    ///      the withdrawal pool.
    /// @param _bondAmount The amount of longs that were closed.
    /// @param _poolBondDelta The amount of bonds that the pool would be
    ///        decreased by if we didn't need to account for the withdrawal
    ///        pool.
    /// @param _shareProceeds The proceeds in shares received from closing the
    ///        long.
    /// @param _sharePrice The current share price.
    /// @param _maturityTime The maturity time of the long.
    function _applyCloseLong(
        uint256 _bondAmount,
        uint256 _poolBondDelta,
        uint256 _shareProceeds,
        uint256 _sharePrice,
        uint256 _maturityTime
    ) internal {
        // Update the long average maturity time.
        longAverageMaturityTime = _calculateAverageMaturityTime(
            longsOutstanding,
            _bondAmount,
            longAverageMaturityTime,
            _maturityTime,
            false
        );

        // Reduce the amount of outstanding longs.
        longsOutstanding -= _bondAmount;

        // If there are outstanding long withdrawal shares, we attribute a
        // proportional amount of the proceeds to the withdrawal pool and the
        // active LPs. Otherwise, we use simplified accounting that has the same
        // behavior but is more gas efficient. Since the difference between the
        // base reserves and the longs outstanding stays the same or gets
        // larger, we don't need to verify the reserves invariants.
        if (longWithdrawalSharesOutstanding > 0) {
            // Calculate the effect that the trade has on the pool's APR.
            uint256 apr = HyperdriveMath.calculateAPRFromReserves(
                shareReserves.sub(_shareProceeds),
                bondReserves.add(_poolBondDelta),
                totalSupply[AssetId._LP_ASSET_ID],
                initialSharePrice,
                positionDuration,
                timeStretch
            );

            // Since longs are backdated to the beginning of the checkpoint and
            // interest only begins accruing when the longs are opened, we
            // exclude the first checkpoint from LP withdrawal payouts. For most
            // pools the difference will not be meaningful, and in edge cases,
            // fees can be tuned to offset the problem.
            uint256 openSharePrice = checkpoints[
                (_maturityTime - positionDuration) + checkpointDuration
            ];

            // Apply the LP proceeds from the trade proportionally to the long
            // withdrawal shares. The accounting for these proceeds is identical
            // to the close short accounting because LPs take the short position
            // when longs are opened. The math for the withdrawal proceeds is
            // given by:
            //
            // proceeds = c_1 * (dy / c_0 - dz) * (min(b_x, dy) / dy)
            uint256 withdrawalAmount = longWithdrawalSharesOutstanding <
                _bondAmount
                ? longWithdrawalSharesOutstanding
                : _bondAmount;
            uint256 withdrawalProceeds = _sharePrice
                .mulDown(
                    _bondAmount.divDown(openSharePrice).sub(_shareProceeds)
                )
                .mulDown(withdrawalAmount.divDown(_bondAmount));

            // Update the long aggregates.
            longWithdrawalSharesOutstanding -= withdrawalAmount;
            longWithdrawalShareProceeds += withdrawalProceeds;

            // Apply the trading deltas to the reserves. These updates reflect
            // the fact that some of the reserves will be attributed to the
            // withdrawal pool. Assuming that there are some withdrawal proceeds,
            // the math for the share reserves update is given by:
            //
            // z -= dz + (dy / c_0 - dz) * (min(b_x, dy) / dy)
            shareReserves -= _shareProceeds.add(
                withdrawalProceeds.divDown(_sharePrice)
            );
            bondReserves = HyperdriveMath.calculateBondReserves(
                shareReserves,
                totalSupply[AssetId._LP_ASSET_ID],
                initialSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
        } else {
            shareReserves -= _shareProceeds;
            bondReserves += _poolBondDelta;
        }
    }

    /// @dev Applies the trading deltas from a closed short to the reserves and
    ///      the withdrawal pool.
    /// @param _bondAmount The amount of shorts that were closed.
    /// @param _poolBondDelta The amount of bonds that the pool would be
    ///        decreased by if we didn't need to account for the withdrawal
    ///        pool.
    /// @param _sharePayment The payment in shares required to close the short.
    /// @param _sharePrice The current share price.
    /// @param _maturityTime The maturity time of the short.
    function _applyCloseShort(
        uint256 _bondAmount,
        uint256 _poolBondDelta,
        uint256 _sharePayment,
        uint256 _sharePrice,
        uint256 _maturityTime
    ) internal {
        // Update the short average maturity time.
        shortAverageMaturityTime = _calculateAverageMaturityTime(
            shortsOutstanding,
            _bondAmount,
            shortAverageMaturityTime,
            _maturityTime,
            false
        );

        // Decrease the amount of shorts outstanding.
        shortsOutstanding -= _bondAmount;

        // If there are outstanding short withdrawal shares, we attribute a
        // proportional amount of the proceeds to the withdrawal pool and the
        // active LPs. Otherwise, we use simplified accounting that has the same
        // behavior but is more gas efficient. Since the difference between the
        // base reserves and the longs outstanding stays the same or gets
        // larger, we don't need to verify the reserves invariants.
        if (shortWithdrawalSharesOutstanding > 0) {
            // Calculate the effect that the trade has on the pool's APR.
            uint256 apr = HyperdriveMath.calculateAPRFromReserves(
                shareReserves.add(_sharePayment),
                bondReserves.sub(_poolBondDelta),
                totalSupply[AssetId._LP_ASSET_ID],
                initialSharePrice,
                positionDuration,
                timeStretch
            );

            // Apply the LP proceeds from the trade proportionally to the short
            // withdrawal pool. The accounting for these proceeds is identical
            // to the close long accounting because LPs take on a long position when
            // shorts are opened. The math for the withdrawal proceeds is given
            // by:
            //
            // proceeds = c_1 * dz * (min(b_y, dy) / dy)
            uint256 withdrawalAmount = shortWithdrawalSharesOutstanding <
                _bondAmount
                ? shortWithdrawalSharesOutstanding
                : _bondAmount;
            uint256 withdrawalProceeds = _sharePrice
                .mulDown(_sharePayment)
                .mulDown(withdrawalAmount.divDown(_bondAmount));
            shortWithdrawalSharesOutstanding -= withdrawalAmount;
            shortWithdrawalShareProceeds += withdrawalProceeds;

            // Apply the trading deltas to the reserves. These updates reflect
            // the fact that some of the reserves will be attributed to the
            // withdrawal pool. The math for the share reserves update is given by:
            //
            // z += dz - dz * (min(b_y, dy) / dy)
            shareReserves += _sharePayment.sub(
                withdrawalProceeds.divDown(_sharePrice)
            );
            bondReserves = HyperdriveMath.calculateBondReserves(
                shareReserves,
                totalSupply[AssetId._LP_ASSET_ID],
                initialSharePrice,
                apr,
                positionDuration,
                timeStretch
            );
        } else {
            shareReserves += _sharePayment;
            bondReserves -= _poolBondDelta;
        }
    }

    // TODO: If we find that this checkpointing flow is too heavy (which is
    // quite possible), we can store the share price and update some key metrics
    // about matured positions and add a poking system that performs the rest of
    // the computation.
    //
    /// @dev Creates a new checkpoint if necessary.
    /// @param _checkpointTime The time of the checkpoint to create.
    /// @param _sharePrice The current share price.
    /// @return openSharePrice The open share price of the latest checkpoint.
    function _applyCheckpoint(
        uint256 _checkpointTime,
        uint256 _sharePrice
    ) internal returns (uint256 openSharePrice) {
        // Return early if the checkpoint has already been updated.
        if (checkpoints[_checkpointTime] != 0) {
            return checkpoints[_checkpointTime];
        }

        // Create the share price checkpoint.
        checkpoints[_checkpointTime] = _sharePrice;

        // Pay out the long withdrawal pool for longs that have matured.
        uint256 maturedLongsAmount = totalSupply[
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, _checkpointTime)
        ];
        if (maturedLongsAmount > 0) {
            // TODO: YieldSpaceMath currently returns a positive quantity at
            //       redemption. With this in mind, this will represent a
            //       slight inaccuracy until this problem is fixed.
            _applyCloseLong(
                maturedLongsAmount,
                0,
                maturedLongsAmount,
                _sharePrice,
                _checkpointTime
            );
        }

        // Pay out the short withdrawal pool for shorts that have matured.
        uint256 maturedShortsAmount = totalSupply[
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, _checkpointTime)
        ];
        if (maturedShortsAmount > 0) {
            // TODO: YieldSpaceMath currently returns a positive quantity at
            //       redemption. With this in mind, this will represent a
            //       slight inaccuracy until this problem is fixed.
            _applyCloseShort(
                maturedShortsAmount,
                0,
                maturedShortsAmount,
                _sharePrice,
                _checkpointTime
            );
        }

        return checkpoints[_checkpointTime];
    }

    /// @dev Applies a withdrawal share redemption to the contract's state.
    /// @param _assetId The asset ID of the withdrawal share to redeem.
    /// @param _withdrawalShares The amount of withdrawal shares to redeem.
    /// @param _withdrawalSharesOutstanding The amount of withdrawal shares
    ///        outstanding.
    /// @param _withdrawalShareProceeds The proceeds that have accrued to the
    ///        withdrawal share pool.
    /// @return proceeds The proceeds from redeeming the withdrawal shares.
    function _applyWithdrawalShareRedemption(
        uint256 _assetId,
        uint256 _withdrawalShares,
        uint256 _withdrawalSharesOutstanding,
        uint256 _withdrawalShareProceeds
    ) internal returns (uint256 proceeds) {
        if (_withdrawalShares > 0) {
            // Burn the withdrawal shares.
            _burn(_assetId, msg.sender, _withdrawalShares);

            // Calculate the base released from the withdrawal shares.
            uint256 withdrawalShareProportion = _withdrawalShares.divDown(
                totalSupply[_assetId].sub(_withdrawalSharesOutstanding)
            );
            proceeds = _withdrawalShareProceeds.mulDown(
                withdrawalShareProportion
            );
        }
        return proceeds;
    }

    /// @dev Calculate a new average maturity time when positions are opened or
    ///      closed.
    /// @param _positionsOutstanding The amount of positions outstanding.
    /// @param _positionAmount The position balance being opened or closed.
    /// @param _averageMaturityTime The average maturity time of positions.
    /// @param _positionMaturityTime The maturity time of the position being
    ///        opened or closed.
    /// @param _isOpen A flag indicating that the position is being opened if
    ///        true and that the position is being closed if false.
    /// @return averageMaturityTime The updated average maturity time.
    function _calculateAverageMaturityTime(
        uint256 _positionsOutstanding,
        uint256 _positionAmount,
        uint256 _averageMaturityTime,
        uint256 _positionMaturityTime,
        bool _isOpen
    ) internal pure returns (uint256 averageMaturityTime) {
        if (_isOpen) {
            return
                (_positionsOutstanding.mulDown(_averageMaturityTime))
                    .add(_positionAmount.mulDown(_positionMaturityTime))
                    .divDown(_positionsOutstanding.add(_positionAmount));
        } else {
            return
                (_positionsOutstanding.mulDown(_averageMaturityTime))
                    .sub(_positionAmount.mulDown(_positionMaturityTime))
                    .divDown(_positionsOutstanding.sub(_positionAmount));
        }
    }

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
        return timeRemaining;
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
        return latestCheckpoint;
    }
}
