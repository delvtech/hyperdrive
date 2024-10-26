// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveEvents } from "../interfaces/IHyperdriveEvents.sol";
import { AssetId } from "../libraries/AssetId.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../libraries/HyperdriveMath.sol";
import { LPMath } from "../libraries/LPMath.sol";
import { SafeCast } from "../libraries/SafeCast.sol";
import { HyperdriveBase } from "./HyperdriveBase.sol";
import { HyperdriveMultiToken } from "./HyperdriveMultiToken.sol";

/// @author DELV
/// @title HyperdriveLP
/// @notice Implements the LP accounting for Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveLP is
    IHyperdriveEvents,
    HyperdriveBase,
    HyperdriveMultiToken
{
    using FixedPointMath for uint256;
    using FixedPointMath for int256;
    using LPMath for LPMath.PresentValueParams;
    using SafeCast for int256;
    using SafeCast for uint256;

    /// @dev Allows the first LP to initialize the market with a target APR.
    /// @param _contribution The amount of capital to supply. The units of this
    ///        quantity are either base or vault shares, depending on the value
    ///        of `_options.asBase`.
    /// @param _apr The target APR.
    /// @param _options The options that configure how the operation is settled.
    /// @return lpShares The initial number of LP shares created.
    function _initialize(
        uint256 _contribution,
        uint256 _apr,
        IHyperdrive.Options calldata _options
    ) internal nonReentrant returns (uint256 lpShares) {
        // Check that the message value and base amount are valid.
        _checkMessageValue();

        // Check that the provided options are valid.
        _checkOptions(_options);

        // Ensure that the pool hasn't been initialized yet.
        if (_marketState.isInitialized) {
            revert IHyperdrive.PoolAlreadyInitialized();
        }

        // Deposit the users contribution and get the amount of shares that
        // their contribution was worth.
        (uint256 shareContribution, uint256 vaultSharePrice) = _deposit(
            _contribution,
            _options
        );

        // Ensure that the contribution is large enough to set aside the minimum
        // share reserves permanently. After initialization, none of the LPs
        // will have a claim on the minimum share reserves, and longs and shorts
        // will not be able to consume this liquidity. This ensures that the
        // share reserves are always greater than zero, which prevents a host of
        // numerical issues when we are updating the reserves during normal
        // operations. As an additional precaution, we will also set aside an
        // amount of shares equaling the minimum share reserves as the initial
        // LP contribution from the zero address. This ensures that the total
        // LP supply will always be greater than or equal to the minimum share
        // reserves, which is helping for preventing donation attacks and other
        // numerical issues.
        if (shareContribution < 2 * _minimumShareReserves) {
            revert IHyperdrive.BelowMinimumContribution();
        }
        unchecked {
            lpShares = shareContribution - 2 * _minimumShareReserves;
        }

        // Set the initialized state to true.
        _marketState.isInitialized = true;

        // Calculate the initial reserves. We ensure that the effective share
        // reserves is larger than the minimum share reserves. This ensures that
        // round-trip properties hold after the pool is initialized.
        (
            uint256 shareReserves,
            int256 shareAdjustment,
            uint256 bondReserves
        ) = LPMath.calculateInitialReserves(
                shareContribution,
                vaultSharePrice,
                _initialVaultSharePrice,
                _apr,
                _positionDuration,
                _timeStretch
            );
        if (
            HyperdriveMath.calculateEffectiveShareReserves(
                shareReserves,
                shareAdjustment
            ) < _minimumShareReserves
        ) {
            revert IHyperdrive.InvalidEffectiveShareReserves();
        }

        // Check to see whether or not the initial liquidity will result in
        // invalid price discovery. If the spot price can't be brought to one,
        // we revert to avoid dangerous pool states.
        (
            int256 solvencyAfterMaxLong,
            bool success
        ) = _calculateSolvencyAfterMaxLongSafe(
                shareReserves,
                shareAdjustment,
                bondReserves,
                vaultSharePrice,
                0,
                0
            );
        if (!success || solvencyAfterMaxLong < 0) {
            revert IHyperdrive.CircuitBreakerTriggered();
        }

        // Initialize the reserves.
        _marketState.shareReserves = shareReserves.toUint128();
        _marketState.shareAdjustment = shareAdjustment.toInt128();
        _marketState.bondReserves = bondReserves.toUint128();

        // Mint the minimum share reserves to the zero address as a buffer that
        // ensures that the total LP supply is always greater than or equal to
        // the minimum share reserves. The initializer will receive slightly
        // less shares than they contributed to cover the shares set aside as a
        // buffer on the share reserves and the shares set aside for the zero
        // address, but this is a small price to pay for the added security
        // in practice.
        _mint(AssetId._LP_ASSET_ID, address(0), _minimumShareReserves);
        _mint(AssetId._LP_ASSET_ID, _options.destination, lpShares);

        // Create an initial checkpoint.
        _applyCheckpoint(
            _latestCheckpoint(),
            vaultSharePrice,
            LPMath.SHARE_PROCEEDS_MAX_ITERATIONS,
            true
        );

        // Emit an Initialize event.
        uint256 contribution = _contribution; // avoid stack-too-deep
        uint256 apr = _apr; // avoid stack-too-deep
        IHyperdrive.Options calldata options = _options; // avoid stack-too-deep
        emit Initialize(
            options.destination,
            lpShares,
            contribution,
            vaultSharePrice,
            options.asBase,
            apr,
            options.extraData
        );

        return lpShares;
    }

    /// @dev Allows LPs to supply liquidity for LP shares.
    /// @param _contribution The amount of capital to supply. The units of this
    ///        quantity are either base or vault shares, depending on the value
    ///        of `_options.asBase`.
    /// @param _minLpSharePrice The minimum LP share price the LP is willing
    ///        to accept for their shares. LPs incur negative slippage when
    ///        adding liquidity if there is a net curve position in the market,
    ///        so this allows LPs to protect themselves from high levels of
    ///        slippage. The units of this quantity are either base or vault
    ///        shares, depending on the value of `_options.asBase`.
    /// @param _minApr The minimum APR at which the LP is willing to supply.
    /// @param _maxApr The maximum APR at which the LP is willing to supply.
    /// @param _options The options that configure how the operation is settled.
    /// @return lpShares The number of LP tokens created.
    function _addLiquidity(
        uint256 _contribution,
        uint256 _minLpSharePrice,
        uint256 _minApr,
        uint256 _maxApr,
        IHyperdrive.Options calldata _options
    ) internal nonReentrant isNotPaused returns (uint256 lpShares) {
        // Check that the message value is valid.
        _checkMessageValue();

        // Check that the provided options are valid.
        _checkOptions(_options);

        // Ensure that the contribution is greater than or equal to the minimum
        // transaction amount.
        if (_contribution < _minimumTransactionAmount) {
            revert IHyperdrive.MinimumTransactionAmount();
        }

        // Enforce the slippage guard.
        uint256 apr = HyperdriveMath.calculateSpotAPR(
            _effectiveShareReserves(),
            _marketState.bondReserves,
            _initialVaultSharePrice,
            _positionDuration,
            _timeStretch
        );
        if (apr < _minApr || apr > _maxApr) {
            revert IHyperdrive.InvalidApr();
        }

        // Deposit for the user, this call also transfers from them
        (uint256 shareContribution, uint256 vaultSharePrice) = _deposit(
            _contribution,
            _options
        );

        // Perform a checkpoint.
        uint256 latestCheckpoint = _latestCheckpoint();
        _applyCheckpoint(
            latestCheckpoint,
            vaultSharePrice,
            LPMath.SHARE_PROCEEDS_MAX_ITERATIONS,
            true
        );

        // Calculate the solvency after opening a max long before applying the
        // add liquidity updates. This is a benchmark for the pool's current
        // price discovery. Adding liquidity should not negatively impact price
        // discovery.
        (
            int256 solvencyAfterMaxLongBefore,
            bool success
        ) = _calculateSolvencyAfterMaxLongSafe(
                _marketState.shareReserves,
                _marketState.shareAdjustment,
                _marketState.bondReserves,
                vaultSharePrice,
                _marketState.longExposure,
                _nonNettedLongs(latestCheckpoint + _positionDuration)
            );
        if (!success) {
            revert IHyperdrive.CircuitBreakerTriggered();
        }

        // Ensure that the spot APR is close enough to the previous weighted
        // spot price to fall within the tolerance.
        uint256 contribution = _contribution; // avoid stack-too-deep
        {
            uint256 previousWeightedSpotAPR = HyperdriveMath
                .calculateAPRFromPrice(
                    _checkpoints[latestCheckpoint - _checkpointDuration]
                        .weightedSpotPrice,
                    _positionDuration
                );
            if (
                apr > previousWeightedSpotAPR + _circuitBreakerDelta ||
                (previousWeightedSpotAPR > _circuitBreakerDelta &&
                    apr < previousWeightedSpotAPR - _circuitBreakerDelta)
            ) {
                revert IHyperdrive.CircuitBreakerTriggered();
            }
        }

        // Get the initial value for the total LP supply and the total supply
        // of withdrawal shares before the liquidity is added. The total LP
        // supply is given by `l = l_a + l_w - l_r` where `l_a` is the total
        // supply of active LP shares, `l_w` is the total supply of withdrawal
        // shares, and `l_r` is the amount of withdrawal shares ready for
        // withdrawal.
        uint256 withdrawalSharesOutstanding = _totalSupply[
            AssetId._WITHDRAWAL_SHARE_ASSET_ID
        ] - _withdrawPool.readyToWithdraw;
        uint256 lpTotalSupply = _totalSupply[AssetId._LP_ASSET_ID] +
            withdrawalSharesOutstanding;

        // Calculate the number of LP shares to mint.
        uint256 endingPresentValue;
        uint256 startingPresentValue;
        {
            // Calculate the present value before updating the reserves.
            LPMath.PresentValueParams memory params = _getPresentValueParams(
                vaultSharePrice
            );
            startingPresentValue = LPMath.calculatePresentValue(params);

            // Add the liquidity to the pool's reserves and calculate the new
            // present value.
            _updateLiquidity(shareContribution.toInt256());
            params.shareReserves = _marketState.shareReserves;
            params.shareAdjustment = _marketState.shareAdjustment;
            params.bondReserves = _marketState.bondReserves;
            endingPresentValue = LPMath.calculatePresentValue(params);

            // Revert if the present value decreased after adding liquidity.
            if (endingPresentValue < startingPresentValue) {
                revert IHyperdrive.DecreasedPresentValueWhenAddingLiquidity();
            }

            // NOTE: Round down to underestimate the amount of LP shares minted.
            //
            // The LP shares minted to the LP is derived by solving for the
            // change in LP shares that preserves the ratio of present value to
            // total LP shares. This ensures that LPs are fairly rewarded for
            // adding liquidity. This is given by:
            //
            // PV0 / l0 = PV1 / (l0 + dl) => dl = ((PV1 - PV0) * l0) / PV0
            lpShares = (endingPresentValue - startingPresentValue).mulDivDown(
                lpTotalSupply,
                startingPresentValue
            );

            // Ensure that enough lp shares are minted so that they can be redeemed.
            if (lpShares < _minimumTransactionAmount) {
                revert IHyperdrive.MinimumTransactionAmount();
            }
        }

        // NOTE: Round down to make the check more conservative.
        //
        // Enforce the minimum LP share price slippage guard.
        if (contribution.divDown(lpShares) < _minLpSharePrice) {
            revert IHyperdrive.OutputLimit();
        }

        // Mint LP shares to the supplier.
        _mint(AssetId._LP_ASSET_ID, _options.destination, lpShares);

        // Distribute the excess idle to the withdrawal pool. If the distribute
        // excess idle calculation fails, we revert to avoid allowing the system
        // to enter an unhealthy state. A failure indicates that the present
        // value can't be calculated.
        success = _distributeExcessIdleSafe(vaultSharePrice);
        if (!success) {
            revert IHyperdrive.DistributeExcessIdleFailed();
        }

        // Check to see whether or not adding this liquidity will result in
        // worsened price discovery. If the spot price can't be brought to one
        // and price discovery worsened after adding liquidity, we revert to
        // avoid dangerous pool states.
        uint256 latestCheckpoint_ = latestCheckpoint; // avoid stack-too-deep
        uint256 lpShares_ = lpShares; // avoid stack-too-deep
        IHyperdrive.Options calldata options = _options; // avoid stack-too-deep
        uint256 vaultSharePrice_ = vaultSharePrice; // avoid stack-too-deep
        int256 solvencyAfterMaxLongAfter;
        (
            solvencyAfterMaxLongAfter,
            success
        ) = _calculateSolvencyAfterMaxLongSafe(
            _marketState.shareReserves,
            _marketState.shareAdjustment,
            _marketState.bondReserves,
            vaultSharePrice_,
            _marketState.longExposure,
            _nonNettedLongs(latestCheckpoint_ + _positionDuration)
        );
        if (
            !success ||
            solvencyAfterMaxLongAfter < solvencyAfterMaxLongBefore.min(0)
        ) {
            revert IHyperdrive.CircuitBreakerTriggered();
        }

        // Emit an AddLiquidity event.
        uint256 lpSharePrice = lpTotalSupply == 0
            ? 0 // NOTE: We always round the LP share price down for consistency.
            : startingPresentValue.mulDivDown(vaultSharePrice_, lpTotalSupply);
        emit AddLiquidity(
            options.destination,
            lpShares_,
            contribution,
            vaultSharePrice_,
            options.asBase,
            lpSharePrice,
            options.extraData
        );
    }

    /// @dev Allows an LP to burn shares and withdraw from the pool.
    /// @param _lpShares The LP shares to burn.
    /// @param _minOutputPerShare The minimum amount the LP expects to receive
    ///        for each withdrawal share that is burned. The units of this
    ///        quantity are either base or vault shares, depending on the value
    ///        of `_options.asBase`.
    /// @param _options The options that configure how the operation is settled.
    /// @return proceeds The amount the LP removing liquidity receives. The
    ///        units of this quantity are either base or vault shares, depending
    ///        on the value of `_options.asBase`.
    /// @return withdrawalShares The base that the LP receives buys out some of
    ///         their LP shares, but it may not be sufficient to fully buy the
    ///         LP out. In this case, the LP receives withdrawal shares equal
    ///         in value to the present value they are owed. As idle capital
    ///         becomes available, the pool will buy back these shares.
    function _removeLiquidity(
        uint256 _lpShares,
        uint256 _minOutputPerShare,
        IHyperdrive.Options calldata _options
    )
        internal
        nonReentrant
        returns (uint256 proceeds, uint256 withdrawalShares)
    {
        // Check that the provided options are valid.
        _checkOptions(_options);

        // Ensure that the amount of LP shares to remove is greater than or
        // equal to the minimum transaction amount.
        if (_lpShares < _minimumTransactionAmount) {
            revert IHyperdrive.MinimumTransactionAmount();
        }

        // Perform a checkpoint.
        uint256 vaultSharePrice = _pricePerVaultShare();
        _applyCheckpoint(
            _latestCheckpoint(),
            vaultSharePrice,
            LPMath.SHARE_PROCEEDS_MAX_ITERATIONS,
            true
        );

        // Burn the LP's shares.
        _burn(AssetId._LP_ASSET_ID, msg.sender, _lpShares);

        // Mint an equivalent amount of withdrawal shares.
        _mint(
            AssetId._WITHDRAWAL_SHARE_ASSET_ID,
            _options.destination,
            _lpShares
        );

        // Redeem as many of the withdrawal shares as possible.
        uint256 withdrawalSharesRedeemed;
        (proceeds, withdrawalSharesRedeemed) = _redeemWithdrawalSharesInternal(
            _options.destination,
            _lpShares,
            vaultSharePrice,
            _minOutputPerShare,
            _options
        );
        withdrawalShares = _lpShares - withdrawalSharesRedeemed;

        // Emit a RemoveLiquidity event. If the LP share price calculation
        // fails, we proceed in removing liquidity and just emit the LP share
        // price as zero. This ensures that the system's liveness isn't impacted
        // by temporarily being unable to calculate the present value.
        (uint256 lpSharePrice, ) = _calculateLPSharePriceSafe(vaultSharePrice);
        emit RemoveLiquidity(
            msg.sender, // provider
            _options.destination, // destination
            _lpShares,
            proceeds,
            vaultSharePrice,
            _options.asBase,
            uint256(withdrawalShares),
            lpSharePrice,
            _options.extraData
        );

        return (proceeds, withdrawalShares);
    }

    /// @dev Redeems withdrawal shares by giving the LP a pro-rata amount of the
    ///      withdrawal pool's proceeds. This function redeems the maximum
    ///      amount of the specified withdrawal shares given the amount of
    ///      withdrawal shares ready to withdraw.
    /// @param _withdrawalShares The withdrawal shares to redeem.
    /// @param _minOutputPerShare The minimum amount the LP expects to
    ///        receive for each withdrawal share that is burned. The units of
    ///        this quantity are either base or vault shares, depending on the
    ///        value of `_options.asBase`.
    /// @param _options The options that configure how the operation is settled.
    /// @return proceeds The amount the LP received. The units of this quantity
    ///         are either base or vault shares, depending on the value of
    ///         `_options.asBase`.
    /// @return withdrawalSharesRedeemed The amount of withdrawal shares that
    ///         were redeemed.
    function _redeemWithdrawalShares(
        uint256 _withdrawalShares,
        uint256 _minOutputPerShare,
        IHyperdrive.Options calldata _options
    )
        internal
        nonReentrant
        returns (uint256 proceeds, uint256 withdrawalSharesRedeemed)
    {
        // Check that the provided options are valid.
        _checkOptions(_options);

        // Perform a checkpoint.
        uint256 vaultSharePrice = _pricePerVaultShare();
        _applyCheckpoint(
            _latestCheckpoint(),
            vaultSharePrice,
            LPMath.SHARE_PROCEEDS_MAX_ITERATIONS,
            true
        );

        // Redeem as many of the withdrawal shares as possible.
        (proceeds, withdrawalSharesRedeemed) = _redeemWithdrawalSharesInternal(
            msg.sender,
            _withdrawalShares,
            vaultSharePrice,
            _minOutputPerShare,
            _options
        );

        // Emit a RedeemWithdrawalShares event.
        emit RedeemWithdrawalShares(
            msg.sender, // provider
            _options.destination, // destination
            withdrawalSharesRedeemed,
            proceeds,
            vaultSharePrice,
            _options.asBase,
            _options.extraData
        );

        return (proceeds, withdrawalSharesRedeemed);
    }

    /// @dev Redeems withdrawal shares by giving the LP a pro-rata amount of the
    ///      withdrawal pool's proceeds. This function redeems the maximum
    ///      amount of the specified withdrawal shares given the amount of
    ///      withdrawal shares ready to withdraw.
    /// @param _source The address that owns the withdrawal shares to redeem.
    /// @param _withdrawalShares The withdrawal shares to redeem.
    /// @param _vaultSharePrice The vault share price.
    /// @param _minOutputPerShare The minimum amount the LP expects to
    ///        receive for each withdrawal share that is burned. The units of
    ///        this quantity are either base or vault shares, depending on the
    ///        value of `_options.asBase`.
    /// @param _options The options that configure how the operation is settled.
    /// @return proceeds The amount the LP received. The units of this quantity
    ///         are either base or vault shares, depending on the value of
    ///         `_options.asBase`.
    /// @return withdrawalSharesRedeemed The amount of withdrawal shares that
    ///         were redeemed.
    function _redeemWithdrawalSharesInternal(
        address _source,
        uint256 _withdrawalShares,
        uint256 _vaultSharePrice,
        uint256 _minOutputPerShare,
        IHyperdrive.Options calldata _options
    ) internal returns (uint256 proceeds, uint256 withdrawalSharesRedeemed) {
        // Distribute the excess idle to the withdrawal pool. If the distribute
        // excess idle calculation fails, we proceed with the calculation since
        // LPs should be able to redeem their withdrawal shares for existing
        // withdrawal proceeds regardless of whether or not idle could be
        // distributed.
        _distributeExcessIdleSafe(_vaultSharePrice);

        // Clamp the shares to the total amount of shares ready for withdrawal
        // to avoid unnecessary reverts. We exit early if the user has no shares
        // available to redeem.
        withdrawalSharesRedeemed = _withdrawalShares;
        uint128 readyToWithdraw_ = _withdrawPool.readyToWithdraw;
        if (withdrawalSharesRedeemed > readyToWithdraw_) {
            withdrawalSharesRedeemed = readyToWithdraw_;
        }
        if (withdrawalSharesRedeemed == 0) return (0, 0);

        // We burn the shares from the user.
        _burn(
            AssetId._WITHDRAWAL_SHARE_ASSET_ID,
            _source,
            withdrawalSharesRedeemed
        );

        // NOTE: Round down to underestimate the share proceeds.
        //
        // The LP gets the pro-rata amount of the collected proceeds.
        uint256 shareProceeds = withdrawalSharesRedeemed.mulDivDown(
            _withdrawPool.proceeds,
            readyToWithdraw_
        );

        // Apply the update to the withdrawal pool.
        _withdrawPool.readyToWithdraw =
            readyToWithdraw_ -
            withdrawalSharesRedeemed.toUint128();
        _withdrawPool.proceeds -= shareProceeds.toUint128();

        // Withdraw the share proceeds to the user.
        proceeds = _withdraw(shareProceeds, _vaultSharePrice, _options);

        // NOTE: Round up to make the check more conservative.
        //
        // Enforce the minimum user output per share.
        if (proceeds < _minOutputPerShare.mulUp(withdrawalSharesRedeemed)) {
            revert IHyperdrive.OutputLimit();
        }

        return (proceeds, withdrawalSharesRedeemed);
    }

    /// @dev Distribute as much of the excess idle as possible to the withdrawal
    ///      pool while holding the LP share price constant.
    /// @param _vaultSharePrice The current vault share price.
    /// @return A failure flag indicating if the calculation succeeded.
    function _distributeExcessIdleSafe(
        uint256 _vaultSharePrice
    ) internal returns (bool) {
        return
            _distributeExcessIdleSafe(
                _vaultSharePrice,
                LPMath.SHARE_PROCEEDS_MAX_ITERATIONS
            );
    }

    /// @dev Distribute as much of the excess idle as possible to the withdrawal
    ///      pool while holding the LP share price constant.
    /// @param _vaultSharePrice The current vault share price.
    /// @param _maxIterations The number of iterations to use in the Newton's
    ///        method component of `_distributeExcessIdleSafe`. This defaults to
    ///        `LPMath.SHARE_PROCEEDS_MAX_ITERATIONS` if the specified value is
    ///        smaller than the constant.
    /// @return A failure flag indicating if the calculation succeeded.
    function _distributeExcessIdleSafe(
        uint256 _vaultSharePrice,
        uint256 _maxIterations
    ) internal returns (bool) {
        // If there are no withdrawal shares, then there is nothing to
        // distribute.
        uint256 withdrawalSharesTotalSupply = _totalSupply[
            AssetId._WITHDRAWAL_SHARE_ASSET_ID
        ] - _withdrawPool.readyToWithdraw;
        if (withdrawalSharesTotalSupply == 0) {
            return true;
        }

        // If there is no excess idle, then there is nothing to distribute.
        uint256 idle = _calculateIdleShareReserves(_vaultSharePrice);
        if (idle == 0) {
            return true;
        }

        // Get the distribute excess idle parameters. If this fails for some
        // we return a failure flag so that the caller can handle the failure.
        (
            LPMath.DistributeExcessIdleParams memory params,
            bool success
        ) = _getDistributeExcessIdleParamsSafe(
                idle,
                withdrawalSharesTotalSupply,
                _vaultSharePrice
            );
        if (!success) {
            return false;
        }

        // Calculate the amount of withdrawal shares that should be redeemed
        // and their share proceeds.
        (uint256 withdrawalSharesRedeemed, uint256 shareProceeds) = LPMath
            .calculateDistributeExcessIdle(params, _maxIterations);

        // Remove the withdrawal pool proceeds from the reserves.
        success = _updateLiquiditySafe(-shareProceeds.toInt256());
        if (!success) {
            return false;
        }

        // Update the withdrawal pool's state.
        _withdrawPool.readyToWithdraw += withdrawalSharesRedeemed.toUint128();
        _withdrawPool.proceeds += shareProceeds.toUint128();

        return true;
    }

    /// @dev Updates the pool's liquidity and holds the pool's spot price
    ///      constant.
    /// @param _shareReservesDelta The delta that should be applied to share
    ///        reserves.
    function _updateLiquidity(int256 _shareReservesDelta) internal {
        // Attempt updating the pool's liquidity and revert if the update fails.
        if (!_updateLiquiditySafe(_shareReservesDelta)) {
            revert IHyperdrive.UpdateLiquidityFailed();
        }
    }

    /// @dev Updates the pool's liquidity and holds the pool's spot price
    ///      constant.
    /// @param _shareReservesDelta The delta that should be applied to share
    ///        reserves.
    /// @return A flag indicating if the update succeeded.
    function _updateLiquiditySafe(
        int256 _shareReservesDelta
    ) internal returns (bool) {
        // Calculate the updated reserves and return false if the calculation fails.
        uint256 shareReserves_ = _marketState.shareReserves;
        int256 shareAdjustment_ = _marketState.shareAdjustment;
        uint256 bondReserves_ = _marketState.bondReserves;
        (
            uint256 updatedShareReserves,
            int256 updatedShareAdjustment,
            uint256 updatedBondReserves,
            bool success
        ) = LPMath.calculateUpdateLiquiditySafe(
                shareReserves_,
                shareAdjustment_,
                bondReserves_,
                _minimumShareReserves,
                _shareReservesDelta
            );
        if (!success) {
            return false;
        }

        // Update the market state and return true since the update was successful.
        if (updatedShareReserves != shareReserves_) {
            _marketState.shareReserves = updatedShareReserves.toUint128();
        }
        if (updatedShareAdjustment != shareAdjustment_) {
            _marketState.shareAdjustment = updatedShareAdjustment.toInt128();
        }
        if (updatedBondReserves != bondReserves_) {
            _marketState.bondReserves = updatedBondReserves.toUint128();
        }
        return true;
    }
}
