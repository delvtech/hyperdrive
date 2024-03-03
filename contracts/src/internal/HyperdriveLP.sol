// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

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

        // Ensure that the pool hasn't been initialized yet.
        if (_marketState.isInitialized) {
            revert IHyperdrive.PoolAlreadyInitialized();
        }

        // Deposit the users contribution and get the amount of shares that
        // their contribution was worth.
        (uint256 vaultShares, uint256 vaultSharePrice) = _deposit(
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
        if (vaultShares < 2 * _minimumShareReserves) {
            revert IHyperdrive.BelowMinimumContribution();
        }
        lpShares = vaultShares - 2 * _minimumShareReserves;

        // Set the initialized state to true.
        _marketState.isInitialized = true;

        // Update the reserves. The bond reserves are calculated so that the
        // pool is initialized with the target APR.
        _marketState.shareReserves = vaultShares.toUint128();
        _marketState.bondReserves = HyperdriveMath
            .calculateInitialBondReserves(
                vaultShares,
                _initialVaultSharePrice,
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
        _applyCheckpoint(_latestCheckpoint(), vaultSharePrice);

        // Emit an Initialize event.
        uint256 baseContribution = _convertToBaseFromOption(
            _contribution,
            vaultSharePrice,
            _options
        );
        emit Initialize(
            _options.destination,
            lpShares,
            baseContribution,
            vaultShares,
            _options.asBase,
            _apr
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
        // Check that the message value and base amount are valid.
        _checkMessageValue();
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
        _applyCheckpoint(_latestCheckpoint(), vaultSharePrice);

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
            _updateLiquidity(int256(shareContribution));
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
            // adding liquidity.This is given by:
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
        if (_contribution.divDown(lpShares) < _minLpSharePrice) {
            revert IHyperdrive.OutputLimit();
        }

        // Mint LP shares to the supplier.
        _mint(AssetId._LP_ASSET_ID, _options.destination, lpShares);

        // Distribute the excess idle to the withdrawal pool.
        _distributeExcessIdle(vaultSharePrice);

        // Emit an AddLiquidity event.
        uint256 lpSharePrice = lpTotalSupply == 0
            ? 0 // NOTE: We always round the LP share price down for consistency.
            : startingPresentValue.divDown(lpTotalSupply);
        uint256 baseContribution = _convertToBaseFromOption(
            _contribution,
            vaultSharePrice,
            _options
        );
        emit AddLiquidity(
            _options.destination,
            lpShares,
            // base contribution
            baseContribution,
            // vault shares contribution
            shareContribution,
            _options.asBase,
            lpSharePrice
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
        if (_lpShares < _minimumTransactionAmount) {
            revert IHyperdrive.MinimumTransactionAmount();
        }

        // Perform a checkpoint.
        uint256 vaultSharePrice = _pricePerVaultShare();
        _applyCheckpoint(_latestCheckpoint(), vaultSharePrice);

        // Burn the LP's shares.
        _burn(AssetId._LP_ASSET_ID, msg.sender, _lpShares);

        // Mint an equivalent amount of withdrawal shares.
        _mint(
            AssetId._WITHDRAWAL_SHARE_ASSET_ID,
            _options.destination,
            _lpShares
        );

        // Distribute excess idle to the withdrawal pool.
        _distributeExcessIdle(vaultSharePrice);

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

        // Emit a RemoveLiquidity event.
        emit RemoveLiquidity(
            _options.destination,
            _lpShares,
            // base proceeds
            _convertToBaseFromOption(proceeds, vaultSharePrice, _options),
            // vault shares proceeds
            _convertToVaultSharesFromOption(
                proceeds,
                vaultSharePrice,
                _options
            ),
            _options.asBase,
            uint256(withdrawalShares),
            _calculateLPSharePrice(vaultSharePrice)
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
        // Perform a checkpoint.
        uint256 vaultSharePrice = _pricePerVaultShare();
        _applyCheckpoint(_latestCheckpoint(), vaultSharePrice);

        // Distribute the excess idle to the withdrawal pool prior to redeeming
        // the withdrawal shares.
        _distributeExcessIdle(vaultSharePrice);

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
            _options.destination,
            withdrawalSharesRedeemed,
            // base proceeds
            _convertToBaseFromOption(proceeds, vaultSharePrice, _options),
            // vault shares proceeds
            _convertToVaultSharesFromOption(
                proceeds,
                vaultSharePrice,
                _options
            ),
            _options.asBase
        );

        return (proceeds, withdrawalSharesRedeemed);
    }

    /// @dev Redeems withdrawal shares by giving the LP a pro-rata amount of the
    ///      withdrawal pool's proceeds. This function redeems the maximum
    ///      amount of the specified withdrawal shares given the amount of
    ///      withdrawal shares ready to withdraw.
    /// @param _source The address that owns the withdrawal shares to redeem.
    /// @param _withdrawalShares The withdrawal shares to redeem.
    /// @param _sharePrice The share price.
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
        uint256 _sharePrice,
        uint256 _minOutputPerShare,
        IHyperdrive.Options calldata _options
    ) internal returns (uint256 proceeds, uint256 withdrawalSharesRedeemed) {
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
        proceeds = _withdraw(shareProceeds, _sharePrice, _options);

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
    function _distributeExcessIdle(uint256 _vaultSharePrice) internal {
        // If there are no withdrawal shares, then there is nothing to
        // distribute.
        uint256 withdrawalSharesTotalSupply = _totalSupply[
            AssetId._WITHDRAWAL_SHARE_ASSET_ID
        ] - _withdrawPool.readyToWithdraw;
        if (withdrawalSharesTotalSupply == 0) {
            return;
        }

        // If there is no excess idle, then there is nothing to distribute.
        uint256 idle = _calculateIdleShareReserves(_vaultSharePrice);
        if (idle == 0) {
            return;
        }

        // Calculate the amount of withdrawal shares that should be redeemed
        // and their share proceeds.
        (uint256 withdrawalSharesRedeemed, uint256 shareProceeds) = LPMath
            .calculateDistributeExcessIdle(
                _getDistributeExcessIdleParams(
                    idle,
                    withdrawalSharesTotalSupply,
                    _vaultSharePrice
                )
            );

        // Update the withdrawal pool's state.
        _withdrawPool.readyToWithdraw += withdrawalSharesRedeemed.toUint128();
        _withdrawPool.proceeds += shareProceeds.toUint128();

        // Remove the withdrawal pool proceeds from the reserves.
        _updateLiquidity(-int256(shareProceeds));
    }

    /// @dev Updates the pool's liquidity and holds the pool's spot price constant.
    /// @param _shareReservesDelta The delta that should be applied to share reserves.
    function _updateLiquidity(int256 _shareReservesDelta) internal {
        // Calculate the updated reserves.
        uint256 shareReserves_ = _marketState.shareReserves;
        int256 shareAdjustment_ = _marketState.shareAdjustment;
        uint256 bondReserves_ = _marketState.bondReserves;
        (
            uint256 updatedShareReserves,
            int256 updatedShareAdjustment,
            uint256 updatedBondReserves
        ) = LPMath.calculateUpdateLiquidity(
                shareReserves_,
                shareAdjustment_,
                bondReserves_,
                _minimumShareReserves,
                _shareReservesDelta
            );

        // Update the market state.
        if (updatedShareReserves != shareReserves_) {
            _marketState.shareReserves = updatedShareReserves.toUint128();
        }
        if (updatedShareAdjustment != shareAdjustment_) {
            _marketState.shareAdjustment = updatedShareAdjustment.toInt128();
        }
        if (updatedBondReserves != bondReserves_) {
            _marketState.bondReserves = updatedBondReserves.toUint128();
        }
    }
}
