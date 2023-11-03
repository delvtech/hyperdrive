// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveBase } from "./HyperdriveBase.sol";
import { HyperdriveTWAP } from "./HyperdriveTWAP.sol";
import { IHyperdrive } from "./interfaces/IHyperdrive.sol";
import { IHyperdriveCore } from "./interfaces/IHyperdriveCore.sol";
import { AssetId } from "./libraries/AssetId.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { HyperdriveMath } from "./libraries/HyperdriveMath.sol";
import { SafeCast } from "./libraries/SafeCast.sol";

/// @author DELV
/// @title HyperdriveLP
/// @notice Implements the LP accounting for Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveLP is IHyperdriveCore, HyperdriveTWAP {
    using FixedPointMath for uint256;
    using SafeCast for int256;
    using SafeCast for uint256;

    /// @notice Allows the first LP to initialize the market with a target APR.
    /// @param _contribution The amount of base to supply.
    /// @param _apr The target APR.
    /// @param _options The options that configure how the operation is settled.
    /// @return lpShares The initial number of LP shares created.
    function initialize(
        uint256 _contribution,
        uint256 _apr,
        IHyperdrive.Options calldata _options
    ) external payable nonReentrant returns (uint256 lpShares) {
        // Check that the message value and base amount are valid.
        _checkMessageValue();

        // Ensure that the pool hasn't been initialized yet.
        if (_marketState.isInitialized) {
            revert IHyperdrive.PoolAlreadyInitialized();
        }

        // Deposit the users contribution and get the amount of shares that
        // their contribution was worth.
        (uint256 shares, uint256 sharePrice) = _deposit(
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
        // amount of shares equalling the minimum share reserves as the initial
        // LP contribution from the zero address. This ensures that the total
        // LP supply will always be greater than or equal to the minimum share
        // reserves, which is helping for preventing donation attacks and other
        // numerical issues.
        if (shares < 2 * _minimumShareReserves) {
            revert IHyperdrive.BelowMinimumContribution();
        }
        lpShares = shares - 2 * _minimumShareReserves;

        // Set the initialized state to true.
        _marketState.isInitialized = true;

        // Update the reserves. The bond reserves are calculated so that the
        // pool is initialized with the target APR.
        _marketState.shareReserves = shares.toUint128();
        _marketState.bondReserves = HyperdriveMath
            .calculateInitialBondReserves(
                shares,
                _initialSharePrice,
                _apr,
                _positionDuration,
                _timeStretch
            )
            .toUint128();

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
        _applyCheckpoint(_latestCheckpoint(), sharePrice);

        // Emit an Initialize event.
        emit Initialize(_options.destination, lpShares, _contribution, _apr);

        return lpShares;
    }

    /// @notice Allows LPs to supply liquidity for LP shares.
    /// @param _contribution The amount of base to supply.
    /// @param _minApr The minimum APR at which the LP is willing to supply.
    /// @param _maxApr The maximum APR at which the LP is willing to supply.
    /// @param _options The options that configure how the operation is settled.
    /// @return lpShares The number of LP tokens created
    function addLiquidity(
        uint256 _contribution,
        uint256 _minApr,
        uint256 _maxApr,
        IHyperdrive.Options calldata _options
    ) external payable nonReentrant isNotPaused returns (uint256 lpShares) {
        // Check that the message value and base amount are valid.
        _checkMessageValue();
        if (_contribution < _minimumTransactionAmount) {
            revert IHyperdrive.MinimumTransactionAmount();
        }

        // Enforce the slippage guard.
        uint256 apr = HyperdriveMath.calculateSpotAPR(
            _effectiveShareReserves(),
            _marketState.bondReserves,
            _initialSharePrice,
            _positionDuration,
            _timeStretch
        );
        if (apr < _minApr || apr > _maxApr) revert IHyperdrive.InvalidApr();

        // Deposit for the user, this call also transfers from them
        (uint256 shares, uint256 sharePrice) = _deposit(
            _contribution,
            _options
        );

        // Perform a checkpoint.
        _applyCheckpoint(_latestCheckpoint(), sharePrice);

        // Get the initial value for the total LP supply and the total supply
        // of withdrawal shares before the liquidity is added. The total LP
        // supply is given by `l = l_a + l_w - l_r` where `l_a` is the total
        // supply of active LP shares, `l_w` is the total supply of withdrawal
        // shares, and `l_r` is the amount of withdrawal shares ready for
        // withdrawal.
        //
        // FIXME: Can we use a `_calculateLPTotalSupply` function?
        uint256 withdrawalSharesOutstanding = _totalSupply[
            AssetId._WITHDRAWAL_SHARE_ASSET_ID
        ] - _withdrawPool.readyToWithdraw;
        uint256 lpTotalSupply = _totalSupply[AssetId._LP_ASSET_ID] +
            withdrawalSharesOutstanding;

        // Calculate the number of LP shares to mint.
        uint256 endingPresentValue;
        {
            // Calculate the present value before updating the reserves.
            HyperdriveMath.PresentValueParams
                memory params = _getPresentValueParams(sharePrice);
            uint256 startingPresentValue = HyperdriveMath.calculatePresentValue(
                params
            );

            // Add the liquidity to the pool's reserves and calculate the new
            // present value.
            _updateLiquidity(int256(shares));
            params.shareReserves = _marketState.shareReserves;
            params.shareAdjustment = _marketState.shareAdjustment;
            params.bondReserves = _marketState.bondReserves;
            endingPresentValue = HyperdriveMath.calculatePresentValue(params);

            // The LP shares minted to the LP is derived by solving for the
            // change in LP shares that preserves the ratio of present value to
            // total LP shares. This ensures that LPs are fairly rewarded for
            // adding liquidity.This is given by:
            //
            // PV0 / l0 = PV1 / (l0 + dl) => dl = ((PV1 - PV0) * l0) / PV0
            lpShares = (endingPresentValue - startingPresentValue).mulDivDown(
                lpTotalSupply,
                startingPresentValue
            );
        }

        // Mint LP shares to the supplier.
        _mint(AssetId._LP_ASSET_ID, _options.destination, lpShares);

        // Distribute the excess idle to the withdrawal pool.
        _distributeExcessIdle(sharePrice);

        // Emit an AddLiquidity event.
        emit AddLiquidity(_options.destination, lpShares, _contribution);
    }

    /// @notice Allows an LP to burn shares and withdraw from the pool.
    /// @param _shares The LP shares to burn.
    /// @param _minOutput The minium amount of the base token to receive.Note - this
    ///        value is likely to be less than the amount LP shares are worth.
    ///        The remainder is in short and long withdraw shares which are hard
    ///        to game the value of.
    /// @param _options The options that configure how the operation is settled.
    /// @return baseProceeds The base the LP removing liquidity receives. The
    ///         LP receives a proportional amount of the pool's idle capital
    /// @return withdrawalShares The base that the LP receives buys out some of
    ///         their LP shares, but it may not be sufficient to fully buy the
    ///         LP out. In this case, the LP receives withdrawal shares equal
    ///         in value to the present value they are owed. As idle capital
    ///         becomes available, the pool will buy back these shares.
    function removeLiquidity(
        uint256 _shares,
        uint256 _minOutput,
        IHyperdrive.Options calldata _options
    )
        external
        nonReentrant
        returns (uint256 baseProceeds, uint256 withdrawalShares)
    {
        if (_shares < _minimumTransactionAmount) {
            revert IHyperdrive.MinimumTransactionAmount();
        }

        // Perform a checkpoint.
        uint256 sharePrice = _pricePerShare();
        _applyCheckpoint(_latestCheckpoint(), sharePrice);

        // Distribute the excess idle to the withdrawal pool prior to removing
        // liquidity from the pool. This prevents us from needing to backtrack
        // from the backend of the calculation.
        _distributeExcessIdle(sharePrice);

        // Burn the LP shares.
        uint256 totalActiveLpSupply = _totalSupply[AssetId._LP_ASSET_ID];
        uint256 withdrawalSharesOutstanding = _totalSupply[
            AssetId._WITHDRAWAL_SHARE_ASSET_ID
        ] - _withdrawPool.readyToWithdraw;
        uint256 totalLpSupply = totalActiveLpSupply +
            withdrawalSharesOutstanding;
        _burn(AssetId._LP_ASSET_ID, msg.sender, _shares);

        // Remove the liquidity from the pool.
        uint256 shareProceeds;
        (shareProceeds, withdrawalShares) = _applyRemoveLiquidity(
            _shares,
            sharePrice,
            totalLpSupply,
            totalActiveLpSupply,
            withdrawalSharesOutstanding
        );

        // Mint the withdrawal shares to the LP.
        _mint(
            AssetId._WITHDRAWAL_SHARE_ASSET_ID,
            _options.destination,
            withdrawalShares
        );

        // Withdraw the shares from the yield source.
        baseProceeds = _withdraw(shareProceeds, _options);

        // Enforce min user outputs
        if (_minOutput > baseProceeds) revert IHyperdrive.OutputLimit();

        // Emit a RemoveLiquidity event.
        uint256 shares = _shares;
        emit RemoveLiquidity(
            _options.destination,
            shares,
            baseProceeds,
            uint256(withdrawalShares)
        );

        return (baseProceeds, withdrawalShares);
    }

    /// @notice Redeems withdrawal shares by giving the LP a pro-rata amount of
    ///         the withdrawal pool's proceeds. This function redeems the
    ///         maximum amount of the specified withdrawal shares given the
    ///         amount of withdrawal shares ready to withdraw.
    /// @param _shares The withdrawal shares to redeem.
    /// @param _minOutputPerShare The minimum amount of base the LP expects to
    ///        receive for each withdrawal share that is burned.
    /// @param _options The options that configure how the operation is settled.
    /// @return baseProceeds The amount of base the LP received.
    /// @return sharesRedeemed The amount of withdrawal shares that were redeemed.
    function redeemWithdrawalShares(
        uint256 _shares,
        uint256 _minOutputPerShare,
        IHyperdrive.Options calldata _options
    )
        external
        nonReentrant
        returns (uint256 baseProceeds, uint256 sharesRedeemed)
    {
        // Perform a checkpoint.
        uint256 sharePrice = _pricePerShare();
        _applyCheckpoint(_latestCheckpoint(), sharePrice);

        // Distribute the excess idle to the withdrawal pool prior to redeeming
        // the withdrawal shares.
        _distributeExcessIdle(sharePrice);

        // Clamp the shares to the total amount of shares ready for withdrawal
        // to avoid unnecessary reverts. We exit early if the user has no shares
        // available to redeem.
        sharesRedeemed = _shares;
        uint128 readyToWithdraw_ = _withdrawPool.readyToWithdraw;
        if (sharesRedeemed > readyToWithdraw_) {
            sharesRedeemed = readyToWithdraw_;
        }
        if (sharesRedeemed == 0) return (0, 0);

        // We burn the shares from the user
        _burn(AssetId._WITHDRAWAL_SHARE_ASSET_ID, msg.sender, sharesRedeemed);

        // The LP gets the pro-rata amount of the collected proceeds.
        uint128 proceeds_ = _withdrawPool.proceeds;
        uint256 shareProceeds = sharesRedeemed.mulDivDown(
            uint128(proceeds_),
            uint128(readyToWithdraw_)
        );

        // Apply the update to the withdrawal pool.
        _withdrawPool.readyToWithdraw =
            readyToWithdraw_ -
            sharesRedeemed.toUint128();
        _withdrawPool.proceeds -= shareProceeds.toUint128();

        // Withdraw for the user
        baseProceeds = _withdraw(shareProceeds, _options);

        // Enforce the minimum user output per share.
        if (_minOutputPerShare.mulDown(sharesRedeemed) > baseProceeds) {
            revert IHyperdrive.OutputLimit();
        }

        // Emit a RedeemWithdrawalShares event.
        emit RedeemWithdrawalShares(
            _options.destination,
            sharesRedeemed,
            baseProceeds
        );

        return (baseProceeds, sharesRedeemed);
    }

    /// @dev Updates the pool's liquidity and holds the pool's spot price constant.
    /// @param _shareReservesDelta The delta that should be applied to share reserves.
    function _updateLiquidity(int256 _shareReservesDelta) internal {
        // If the share reserves delta is zero, we can return early since no
        // action is needed.
        if (_shareReservesDelta == 0) {
            return;
        }

        // Ensure that the share reserves are greater than or equal to the
        // minimum share reserves. This invariant should never break. If it
        // breaks, all activity should cease.
        uint256 shareReserves = _marketState.shareReserves;
        if (shareReserves < _minimumShareReserves) {
            revert IHyperdrive.InvalidShareReserves();
        }

        // Update the share reserves by applying the share reserves delta. We
        // ensure that our minimum share reserves invariant is still maintained.
        int256 updatedShareReserves = int256(shareReserves) +
            _shareReservesDelta;
        if (updatedShareReserves < int256(_minimumShareReserves)) {
            revert IHyperdrive.InvalidShareReserves();
        }
        _marketState.shareReserves = uint256(updatedShareReserves).toUint128();

        // Update the share adjustment by holding the ratio of share reserves
        // to share adjustment proportional. In general, our pricing model cannot
        // support negative values for the z coordinate, so this is important as
        // it ensures that if z - zeta starts as a positive value, it ends as a
        // positive value. With this in mind, we update the share adjustment as:
        //
        // zeta_old / z_old = zeta_new / z_new => zeta_new = zeta_old * (z_new / z_old)
        int256 updatedShareAdjustment;
        int256 shareAdjustment = _marketState.shareAdjustment;
        if (shareAdjustment >= 0) {
            updatedShareAdjustment = int256(
                uint256(updatedShareReserves).mulDivDown(
                    uint256(shareAdjustment),
                    shareReserves
                )
            );
        } else {
            updatedShareAdjustment = -int256(
                uint256(updatedShareReserves).mulDivDown(
                    uint256(-shareAdjustment),
                    shareReserves
                )
            );
        }
        _marketState.shareAdjustment = updatedShareAdjustment.toInt128();

        // The liquidity update should hold the spot price invariant. The spot
        // price of base in terms of bonds is given by:
        //
        // p = (mu * (z - zeta) / y) ** tau
        //
        // This formula implies that holding the ratio of share reserves to bond
        // reserves constant will hold the spot price constant. This allows us
        // to calculate the updated bond reserves as:
        //
        // (z_old - zeta_old) / y_old = (z_new - zeta_new) / y_new
        //                          =>
        // y_new = (z_new - zeta_new) * (y_old / (z_old - zeta_old))
        _marketState.bondReserves = HyperdriveMath
            .calculateEffectiveShareReserves(
                uint256(updatedShareReserves),
                updatedShareAdjustment
            )
            .mulDivDown(
                _marketState.bondReserves,
                HyperdriveMath.calculateEffectiveShareReserves(
                    shareReserves,
                    shareAdjustment
                )
            )
            .toUint128();
    }

    /// @dev Removes liquidity from the pool and calculates the amount of
    ///      withdrawal shares that should be minted.
    /// @param _shares The amount of shares to remove.
    /// @param _sharePrice The current price of a share.
    /// @param _totalLpSupply The total amount of LP shares.
    /// @param _totalActiveLpSupply The total amount of active LP shares.
    /// @param _withdrawalSharesOutstanding The total amount of withdrawal
    ///        shares outstanding.
    /// @return shareProceeds The share proceeds that will be paid to the LP.
    /// @return The amount of withdrawal shares that should be minted.
    function _applyRemoveLiquidity(
        uint256 _shares,
        uint256 _sharePrice,
        uint256 _totalLpSupply,
        uint256 _totalActiveLpSupply,
        uint256 _withdrawalSharesOutstanding
    ) internal returns (uint256 shareProceeds, uint256) {
        // The LP is given their share of the idle capital in the pool. Since we
        // distributed the excess idle to the withdrawal pool, we assume that
        // the active LPs are the only LPs entitled to the pool's
        // idle capital. The LP's proceeds are calculated as:
        //
        // proceeds = idle * (dl / l_a)
        HyperdriveMath.PresentValueParams
            memory params = _getPresentValueParams(_sharePrice);
        uint256 startingPresentValue = HyperdriveMath.calculatePresentValue(
            params
        );
        shareProceeds = _calculateIdleShareReserves(_pricePerShare());
        shareProceeds = shareProceeds.mulDivDown(_shares, _totalActiveLpSupply);
        _updateLiquidity(-int256(shareProceeds));
        params.shareReserves = _marketState.shareReserves;
        params.shareAdjustment = _marketState.shareAdjustment;
        params.bondReserves = _marketState.bondReserves;
        uint256 endingPresentValue = HyperdriveMath.calculatePresentValue(
            params
        );

        // Calculate the amount of withdrawal shares that should be minted. We
        // solve for this value by solving the present value equation as
        // follows:
        //
        // PV0 / l0 = PV1 / (l0 - dl + dw) => dw = (PV1 / PV0) * l0 - (l0 - dl)
        int256 withdrawalShares = int256(
            _totalLpSupply.mulDivDown(endingPresentValue, startingPresentValue)
        );
        withdrawalShares -= int256(_totalLpSupply) - int256(_shares);
        if (withdrawalShares < 0) {
            // We backtrack by calculating the amount of the idle that should
            // be returned to the pool using the original present value ratio.
            uint256 overestimatedProceeds = startingPresentValue.mulDivDown(
                uint256(-withdrawalShares),
                _totalLpSupply
            );
            shareProceeds -= overestimatedProceeds;
            _updateLiquidity(int256(overestimatedProceeds));
            _applyWithdrawalProceeds(
                overestimatedProceeds,
                _withdrawalSharesOutstanding,
                _sharePrice
            );
            delete withdrawalShares;
        }

        return (shareProceeds, uint256(withdrawalShares));
    }

    /// @dev If the idle capital in the pool is worth more than the active LP
    ///      supply, then we pay out the withdrawal pool with the excess idle.
    /// @param _sharePrice The current share price.
    function _distributeExcessIdle(uint256 _sharePrice) internal {
        // Calculate the value of the active LP shares as:
        //
        // activeLpValue = l_a * (PV / l).
        uint256 activeLpSupply = _totalSupply[AssetId._LP_ASSET_ID];
        uint256 withdrawalSharesOutstanding = _totalSupply[
            AssetId._WITHDRAWAL_SHARE_ASSET_ID
        ] - _withdrawPool.readyToWithdraw;
        uint256 totalLpSupply = activeLpSupply + withdrawalSharesOutstanding;
        uint256 presentValue = HyperdriveMath.calculatePresentValue(
            _getPresentValueParams(_sharePrice)
        );
        uint256 activeLpValue = activeLpSupply.mulDivDown(
            presentValue,
            totalLpSupply
        );

        // If the value of the active LP shares is less than the idle capital,
        // then all of the active LPs could be paid out in base with liquidity
        // to spare. We pay out this excess idle to the withdrawal pool. In
        // the case that the pool's present value is zero, all of the
        // withdrawal shares are paid out.
        uint256 withdrawalProceeds = 0;
        uint256 idle = _calculateIdleShareReserves(_sharePrice);
        if (idle > activeLpValue) {
            withdrawalProceeds = idle - activeLpValue;
        }
        if (withdrawalProceeds > 0 || presentValue == 0) {
            _compensateWithdrawalPool(
                withdrawalProceeds,
                presentValue,
                totalLpSupply,
                withdrawalSharesOutstanding
            );
        }
    }

    /// @dev Pays out the maximum amount of withdrawal shares given a specified
    ///      amount of withdrawal proceeds.
    /// @param _withdrawalProceeds The amount of withdrawal proceeds to pay out.
    /// @param _withdrawalSharesOutstanding The amount of withdrawal shares
    ///        that haven't been paid out.
    /// @param _sharePrice The current share price.
    function _applyWithdrawalProceeds(
        uint256 _withdrawalProceeds,
        uint256 _withdrawalSharesOutstanding,
        uint256 _sharePrice
    ) internal {
        uint256 presentValue = HyperdriveMath.calculatePresentValue(
            _getPresentValueParams(_sharePrice)
        );
        uint256 lpTotalSupply = _totalSupply[AssetId._LP_ASSET_ID] +
            _withdrawalSharesOutstanding;
        _compensateWithdrawalPool(
            _withdrawalProceeds,
            presentValue,
            lpTotalSupply,
            _withdrawalSharesOutstanding
        );
    }

    /// @dev Pays out a specified amount of withdrawal proceeds to the
    ///      withdrawal pool. This function is useful for circumstances in which
    ///      core calculations have already been performed to avoid reloading
    ///      state.
    /// @param _withdrawalProceeds The amount of withdrawal proceeds to pay out.
    /// @param _presentValue The present value of the pool.
    /// @param _lpTotalSupply The total supply of LP shares.
    /// @param _withdrawalSharesOutstanding The outstanding withdrawal shares.
    function _compensateWithdrawalPool(
        uint256 _withdrawalProceeds,
        uint256 _presentValue,
        uint256 _lpTotalSupply,
        uint256 _withdrawalSharesOutstanding
    ) internal {
        // Calculate the maximum amount of LP shares that could be paid out by
        // the withdrawal proceeds. The calculation uses the ratio of present
        // value to LP total supply as follows:
        //
        // maxSharesReleased = withdrawalProceeds * (l / PV)
        //
        // In the event that all of the LPs have removed their liquidity and the
        // remaining positions hit maturity, all of the withdrawal shares are
        // marked as ready to withdraw.
        uint256 maxSharesReleased = _presentValue > 0
            ? _lpTotalSupply.mulDivDown(_withdrawalProceeds, _presentValue)
            : _lpTotalSupply;
        if (maxSharesReleased == 0) return;

        // Calculate the amount of withdrawal shares that will be released and
        // the amount of capital that will be used to pay out the withdrawal
        // pool.
        uint256 sharesReleased = maxSharesReleased;
        uint256 withdrawalPoolProceeds = _withdrawalProceeds;
        if (maxSharesReleased > _withdrawalSharesOutstanding) {
            sharesReleased = _withdrawalSharesOutstanding;
            withdrawalPoolProceeds = _withdrawalProceeds.mulDivDown(
                sharesReleased,
                maxSharesReleased
            );
        }
        _withdrawPool.readyToWithdraw += sharesReleased.toUint128();
        _withdrawPool.proceeds += withdrawalPoolProceeds.toUint128();

        // Remove the withdrawal pool proceeds from the reserves.
        _updateLiquidity(-int256(withdrawalPoolProceeds));
    }
}
