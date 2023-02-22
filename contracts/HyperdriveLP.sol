// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { HyperdriveBase } from "contracts/HyperdriveBase.sol";
import { AssetId } from "contracts/libraries/AssetId.sol";
import { Errors } from "contracts/libraries/Errors.sol";
import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/libraries/HyperdriveMath.sol";

/// @author Delve
/// @title HyperdriveLP
/// @notice Implements the LP accounting for Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveLP is HyperdriveBase {
    using FixedPointMath for uint256;

    /// @notice Allows the first LP to initialize the market with a target APR.
    /// @param _contribution The amount of base to supply.
    /// @param _apr The target APR.
    /// @param _destination The destination of the LP shares.
    /// @param _asUnderlying If true the user is charged in underlying if false
    ///                      the contract transfers in yield source directly.
    ///                      Note - for some paths one choice may be disabled or blocked.
    function initialize(
        uint256 _contribution,
        uint256 _apr,
        address _destination,
        bool _asUnderlying
    ) external {
        // Ensure that the pool hasn't been initialized yet.
        if (shareReserves > 0 || bondReserves > 0) {
            revert Errors.PoolAlreadyInitialized();
        }

        // Deposit for the user, this transfers from them.
        (uint256 shares, uint256 sharePrice) = deposit(
            _contribution,
            _asUnderlying
        );

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
            _destination,
            sharePrice.mulDown(shares).add(bondReserves)
        );
    }

    /// @notice Allows LPs to supply liquidity for LP shares.
    /// @param _contribution The amount of base to supply.
    /// @param _minOutput The minimum number of LP tokens the user should receive
    /// @param _destination The address which will hold the LP shares
    /// @param _asUnderlying If true the user is charged in underlying if false
    ///                      the contract transfers in yield source directly.
    ///                      Note - for some paths one choice may be disabled or blocked.
    /// @return lpShares The number of LP tokens created
    function addLiquidity(
        uint256 _contribution,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256 lpShares) {
        if (_contribution == 0) {
            revert Errors.ZeroAmount();
        }

        // Deposit for the user, this call also transfers from them
        (uint256 shares, uint256 sharePrice) = deposit(
            _contribution,
            _asUnderlying
        );

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

        // To ensure that our LP allocation scheme fairly rewards LPs for adding
        // liquidity, we linearly interpolate between the present and future
        // value of longs and shorts. These interpolated values are the long and
        // short adjustments. The following calculation is used to determine the
        // amount of LP shares rewarded to new LP:
        //
        // lpShares = (dz * l) / (z + a_s - a_l)
        uint256 longAdjustment = HyperdriveMath.calculateLpAllocationAdjustment(
            longsOutstanding,
            longBaseVolume,
            _calculateTimeRemaining(longAverageMaturityTime),
            sharePrice
        );
        uint256 shortAdjustment = HyperdriveMath
            .calculateLpAllocationAdjustment(
                shortsOutstanding,
                shortBaseVolume,
                _calculateTimeRemaining(shortAverageMaturityTime),
                sharePrice
            );
        lpShares = shares.mulDown(totalSupply[AssetId._LP_ASSET_ID]).divDown(
            shareReserves.add(shortAdjustment).sub(longAdjustment)
        );

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

        // Enforce min user outputs
        if (_minOutput > lpShares) revert Errors.OutputLimit();

        // Mint LP shares to the supplier.
        _mint(AssetId._LP_ASSET_ID, _destination, lpShares);
    }

    /// @notice Allows an LP to burn shares and withdraw from the pool.
    /// @param _shares The LP shares to burn.
    /// @param _minOutput The minium amount of the base token to receive.Note - this
    ///                   value is likely to be less than the amount LP shares are worth.
    ///                   The remainder is in short and long withdraw shares which are hard
    ///                   to game the value of.
    /// @param _destination The address which will receive the withdraw proceeds
    /// @param _asUnderlying If true the user is paid in underlying if false
    ///                      the contract transfers in yield source directly.
    ///                      Note - for some paths one choice may be disabled or blocked.
    /// @return Returns the base out, the lond withdraw shares out and the short withdraw
    ///         shares out.
    function removeLiquidity(
        uint256 _shares,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
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

        // Withdraw the shares from the yield source.
        (uint256 baseOutput, ) = withdraw(
            shareProceeds,
            _destination,
            _asUnderlying
        );

        // Enforce min user outputs
        if (_minOutput > baseOutput) revert Errors.OutputLimit();

        return (baseOutput, longWithdrawalShares, shortWithdrawalShares);
    }

    /// @notice Redeems long and short withdrawal shares.
    /// @param _longWithdrawalShares The long withdrawal shares to redeem.
    /// @param _shortWithdrawalShares The short withdrawal shares to redeem.
    /// @param _minOutput The minimum amount of base the LP expects to receive.
    /// @param _destination The address which receive the withdraw proceeds
    /// @param _asUnderlying If true the user is paid in underlying if false
    ///                      the contract transfers in yield source directly.
    ///                      Note - for some paths one choice may be disabled or blocked.
    /// @return _proceeds The amount of base the LP received.
    function redeemWithdrawalShares(
        uint256 _longWithdrawalShares,
        uint256 _shortWithdrawalShares,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256 _proceeds) {

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
        uint256 shareProceeds = proceeds.divDown(sharePrice);
        (_proceeds, ) = withdraw(shareProceeds, _destination, _asUnderlying);

        // Enforce min user outputs
        if (_minOutput > _proceeds) revert Errors.OutputLimit();
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
}
