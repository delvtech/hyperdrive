// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveLP } from "./HyperdriveLP.sol";
import { IHyperdrive } from "./interfaces/IHyperdrive.sol";
import { AssetId } from "./libraries/AssetId.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { HyperdriveMath } from "./libraries/HyperdriveMath.sol";
import { SafeCast } from "./libraries/SafeCast.sol";
import { YieldSpaceMath } from "./libraries/YieldSpaceMath.sol";

/// @author DELV
/// @title HyperdriveShort
/// @notice Implements the short accounting for Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveShort is HyperdriveLP {
    using FixedPointMath for uint256;
    using FixedPointMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;

    /// @notice Opens a short position.
    /// @param _bondAmount The amount of bonds to short.
    /// @param _maxDeposit The most the user expects to deposit for this trade
    /// @param _destination The address which gets credited with share tokens
    /// @param _asUnderlying A flag indicating whether the sender will pay in
    ///        base or using another currency. Implementations choose which
    ///        currencies they accept.
    /// @return maturityTime The maturity time of the short.
    /// @return traderDeposit The amount the user deposited for this trade.
    function openShort(
        uint256 _bondAmount,
        uint256 _maxDeposit,
        address _destination,
        bool _asUnderlying
    )
        external
        payable
        nonReentrant
        isNotPaused
        returns (uint256 maturityTime, uint256 traderDeposit)
    {
        // Check that the message value and base amount are valid.
        _checkMessageValue();
        if (_bondAmount < _minimumTransactionAmount) {
            revert IHyperdrive.MinimumTransactionAmount();
        }

        // Perform a checkpoint and compute the amount of interest the short
        // would have received if they opened at the beginning of the checkpoint.
        // Since the short will receive interest from the beginning of the
        // checkpoint, they will receive this backdated interest back at closing.
        uint256 sharePrice = _pricePerShare();
        uint256 latestCheckpoint = _latestCheckpoint();
        uint256 openSharePrice = _applyCheckpoint(latestCheckpoint, sharePrice);

        // Calculate the pool and user deltas using the trading function. We
        // backdate the bonds sold to the beginning of the checkpoint.
        maturityTime = latestCheckpoint + _positionDuration;
        uint256 shareReservesDelta;
        {
            uint256 totalGovernanceFee;
            (
                traderDeposit,
                shareReservesDelta,
                totalGovernanceFee
            ) = _calculateOpenShort(
                _bondAmount,
                sharePrice,
                openSharePrice,
                FixedPointMath.ONE_18 // shorts are opened with a time remaining of 1
            );

            // Attribute the governance fees.
            _governanceFeesAccrued += totalGovernanceFee;
        }

        // Take custody of the trader's deposit and ensure that the trader
        // doesn't pay more than their max deposit. The trader's deposit is
        // equal to the proceeds that they would receive if they closed
        // immediately (without fees).
        if (_maxDeposit < traderDeposit) revert IHyperdrive.OutputLimit();
        _deposit(traderDeposit, _asUnderlying);

        // Apply the state updates caused by opening the short.
        _applyOpenShort(
            _bondAmount,
            traderDeposit,
            shareReservesDelta,
            sharePrice,
            maturityTime
        );

        // Mint the short tokens to the trader. The ID is a concatenation of the
        // current share price and the maturity time of the shorts.
        uint256 assetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Short,
            maturityTime
        );
        _mint(assetId, _destination, _bondAmount);

        // Emit an OpenShort event.
        uint256 bondAmount = _bondAmount; // Avoid stack too deep error.
        emit OpenShort(
            _destination,
            assetId,
            maturityTime,
            traderDeposit,
            bondAmount
        );

        return (maturityTime, traderDeposit);
    }

    /// @notice Closes a short position with a specified maturity time.
    /// @param _maturityTime The maturity time of the short.
    /// @param _bondAmount The amount of shorts to close.
    /// @param _minOutput The minimum output of this trade.
    /// @param _destination The address which gets the proceeds from closing this short
    /// @param _asUnderlying A flag indicating whether the sender will pay in
    ///        base or using another currency. Implementations choose which
    ///        currencies they accept.
    /// @return The amount of base tokens produced by closing this short
    function closeShort(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external nonReentrant returns (uint256) {
        if (_bondAmount < _minimumTransactionAmount) {
            revert IHyperdrive.MinimumTransactionAmount();
        }

        // Perform a checkpoint.
        uint256 sharePrice = _pricePerShare();
        _applyCheckpoint(_maturityTime, sharePrice);

        // Burn the shorts that are being closed.
        _burn(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, _maturityTime),
            msg.sender,
            _bondAmount
        );

        // Calculate the pool and user deltas using the trading function.
        (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 sharePayment,
            uint256 totalGovernanceFee
        ) = _calculateCloseShort(_bondAmount, sharePrice, _maturityTime);

        // If the ending spot price is greater than 1, we are in the negative
        // interest region of the trading function. The spot price is given by
        // ((mu * (z - zeta)) / y) ** tau, so all that we need to check is that
        // (mu * (z - zeta)) / y <= 1. With this in mind, we can use a revert
        // condition of mu * (z - zeta) > y.
        if (
            _initialSharePrice.mulDown(
                _effectiveShareReserves() + shareReservesDelta
            ) > _marketState.bondReserves - bondReservesDelta
        ) {
            revert IHyperdrive.NegativeInterest();
        }

        // If the position hasn't matured, apply the accounting updates that
        // result from closing the short to the reserves and pay out the
        // withdrawal pool if necessary.
        if (block.timestamp < _maturityTime) {
            // Attribute the governance fees.
            _governanceFeesAccrued += totalGovernanceFee;
            uint256 sharePaymentWithoutFees = sharePayment - totalGovernanceFee;
            uint256 maturityTime_ = _maturityTime; // Avoid stack too deep error.
            _applyCloseShort(
                _bondAmount,
                bondReservesDelta,
                sharePaymentWithoutFees,
                shareReservesDelta,
                maturityTime_
            );

            // Update the checkpoint and global longExposure
            uint256 checkpointTime = maturityTime_ - _positionDuration;
            int128 checkpointExposureBefore = int128(
                _checkpoints[checkpointTime].longExposure
            );
            _updateCheckpointLongExposureOnClose(
                _bondAmount,
                shareReservesDelta,
                bondReservesDelta,
                sharePaymentWithoutFees,
                maturityTime_,
                sharePrice,
                false
            );
            _updateLongExposure(
                checkpointExposureBefore,
                _checkpoints[checkpointTime].longExposure
            );

            // Distribute the excess idle to the withdrawal pool.
            _distributeExcessIdle(sharePrice);
        }

        // Withdraw the profit to the trader. This includes the proceeds from
        // the short sale as well as the variable interest that was collected
        // on the face value of the bonds:
        uint256 openSharePrice = _checkpoints[_maturityTime - _positionDuration]
            .sharePrice;
        uint256 closeSharePrice = _maturityTime <= block.timestamp
            ? _checkpoints[_maturityTime].sharePrice
            : sharePrice;
        uint256 shortProceeds = HyperdriveMath.calculateShortProceeds(
            _bondAmount,
            sharePayment,
            openSharePrice,
            closeSharePrice,
            sharePrice,
            _flatFee
        );
        uint256 baseProceeds = _withdraw(
            shortProceeds,
            _destination,
            _asUnderlying
        );

        // Enforce min user outputs
        if (baseProceeds < _minOutput) revert IHyperdrive.OutputLimit();

        // Emit a CloseShort event.
        uint256 maturityTime = _maturityTime; // Avoid stack too deep error.
        uint256 bondAmount = _bondAmount; // Avoid stack too deep error.
        emit CloseShort(
            _destination,
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, maturityTime),
            maturityTime,
            baseProceeds,
            bondAmount
        );

        return baseProceeds;
    }

    /// @dev Applies an open short to the state. This includes updating the
    ///      reserves and maintaining the reserve invariants.
    /// @param _bondAmount The amount of bonds shorted.
    /// @param _traderDeposit The amount of base tokens deposited by the trader.
    /// @param _shareReservesDelta The amount of shares paid to the curve.
    /// @param _sharePrice The share price.
    /// @param _maturityTime The maturity time of the long.
    function _applyOpenShort(
        uint256 _bondAmount,
        uint256 _traderDeposit,
        uint256 _shareReservesDelta,
        uint256 _sharePrice,
        uint256 _maturityTime
    ) internal {
        // Update the average maturity time of long positions.
        _marketState.shortAverageMaturityTime = uint256(
            _marketState.shortAverageMaturityTime
        )
            .updateWeightedAverage(
                _marketState.shortsOutstanding,
                _maturityTime * 1e18, // scale up to fixed point scale
                _bondAmount,
                true
            )
            .toUint128();

        // Apply the trading deltas to the reserves and increase the bond buffer
        // by the amount of bonds that were shorted. We don't need to add the
        // margin or pre-paid interest to the reserves because of the way that
        // the close short accounting works.
        uint128 shareReserves_ = _marketState.shareReserves -
            _shareReservesDelta.toUint128();
        _marketState.shareReserves = shareReserves_;
        _marketState.bondReserves += _bondAmount.toUint128();
        _marketState.shortsOutstanding += _bondAmount.toUint128();

        // TODO: We're not sure what causes the z >= zeta check to fail.
        // It may be unnecessary, but that needs to be proven before we can
        // remove it.
        //
        // The share reserves are decreased in this operation, so we need to
        // verify that our invariants that z >= z_min and z >= zeta
        // are satisfied. The former is checked when we check solvency (since
        // global exposure is greater than or equal to zero, z < z_min
        // implies z - e/c - z_min < 0.
        if (
            int256(uint256(_marketState.shareReserves)) <
            _marketState.shareAdjustment
        ) {
            revert IHyperdrive.InvalidShareReserves();
        }

        // Update the checkpoint's short deposits and decrease the long exposure.
        // NOTE: Refer to this issue for details on if this should be moved
        //       https://github.com/delvtech/hyperdrive/issues/558
        uint256 _latestCheckpoint = _latestCheckpoint();
        int128 checkpointExposureBefore = int128(
            _checkpoints[_latestCheckpoint].longExposure
        );
        uint256 shortAssetsDelta = _traderDeposit + _bondAmount;
        _checkpoints[_latestCheckpoint].longExposure -= int128(
            shortAssetsDelta.toUint128()
        );
        _updateLongExposure(
            checkpointExposureBefore,
            _checkpoints[_latestCheckpoint].longExposure
        );

        // Opening a short decreases the system's exposure because the short's
        // margin can be used to offset some of the long exposure. Despite this,
        // opening a short decreases the share reserves, which limits the amount
        // of capital available to back non-netted long exposure. Since both
        // quantities decrease, we need to check that the system is still solvent.
        if (!_isSolvent(_sharePrice)) {
            revert IHyperdrive.BaseBufferExceedsShareReserves();
        }

        // Distribute the excess idle to the withdrawal pool.
        _distributeExcessIdle(_sharePrice);
    }

    /// @dev Applies the trading deltas from a closed short to the reserves and
    ///      the withdrawal pool.
    /// @param _bondAmount The amount of shorts that were closed.
    /// @param _bondReservesDelta The amount of bonds paid by the curve.
    /// @param _sharePayment The payment in shares required to close the short.
    /// @param _shareReservesDelta The amount of bonds paid to the curve.
    /// @param _maturityTime The maturity time of the short.
    function _applyCloseShort(
        uint256 _bondAmount,
        uint256 _bondReservesDelta,
        uint256 _sharePayment,
        uint256 _shareReservesDelta,
        uint256 _maturityTime
    ) internal {
        {
            uint128 shortsOutstanding_ = _marketState.shortsOutstanding;
            // Update the short average maturity time.
            _marketState.shortAverageMaturityTime = uint256(
                _marketState.shortAverageMaturityTime
            )
                .updateWeightedAverage(
                    shortsOutstanding_,
                    _maturityTime * 1e18, // scale up to fixed point scale
                    _bondAmount,
                    false
                )
                .toUint128();

            // Decrease the amount of shorts outstanding.
            _marketState.shortsOutstanding =
                shortsOutstanding_ -
                _bondAmount.toUint128();
        }

        // Apply the updates from the curve and flat components of the trade to
        // the reserves. The share proceeds are added to the share reserves
        // since the LPs are selling bonds for shares.  The bond reserves are
        // decreased by the curve component to increase the spot price. The
        // share adjustment is increased by the flat component of the share
        // reserves update so that we can translate the curve to hold the
        // pricing invariant under the flat update.
        _marketState.shareReserves += _sharePayment.toUint128();
        _marketState.shareAdjustment += int256(
            _sharePayment - _shareReservesDelta
        ).toInt128();
        _marketState.bondReserves -= _bondReservesDelta.toUint128();
    }

    /// @dev Calculate the pool reserve and trader deltas that result from
    ///      opening a short. This calculation includes trading fees.
    /// @param _bondAmount The amount of bonds being sold to open the short.
    /// @param _sharePrice The current share price.
    /// @param _openSharePrice The share price at the beginning of the checkpoint.
    /// @param _timeRemaining The time remaining in the position.
    /// @return traderDeposit The deposit required to open the short.
    /// @return shareReservesDelta The change in the share reserves.
    /// @return totalGovernanceFee The governance fee in shares.
    function _calculateOpenShort(
        uint256 _bondAmount,
        uint256 _sharePrice,
        uint256 _openSharePrice,
        uint256 _timeRemaining
    )
        internal
        returns (
            uint256 traderDeposit,
            uint256 shareReservesDelta,
            uint256 totalGovernanceFee
        )
    {
        // Calculate the effect that opening the short should have on the pool's
        // reserves as well as the amount of shares the trader receives from
        // selling the shorted bonds at the market price.
        shareReservesDelta = HyperdriveMath.calculateOpenShort(
            _effectiveShareReserves(),
            _marketState.bondReserves,
            _bondAmount,
            _timeStretch,
            _sharePrice,
            _initialSharePrice
        );

        // If the base proceeds of selling the bonds is greater than the bond
        // amount, then the trade occurred in the negative interest domain. We
        // revert in these pathological cases.
        if (shareReservesDelta.mulDown(_sharePrice) > _bondAmount)
            revert IHyperdrive.NegativeInterest();

        // Calculate the fees charged on the curve and flat parts of the trade.
        // Since we calculate the amount of shares received given bonds in, we
        // subtract the fee from the share deltas so that the trader receives
        // less shares.
        uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
            _effectiveShareReserves(),
            _marketState.bondReserves,
            _initialSharePrice,
            _timeStretch
        );

        // Add the spot price to the oracle if an oracle update is required
        recordPrice(spotPrice);

        // Calculate the fees charged to the user (totalCurveFe) and the portion of those
        // fees that are paid to governance (governanceCurveFee).
        uint256 totalCurveFee;
        (
            totalCurveFee, // there is no flat fee on opening shorts
            ,
            totalGovernanceFee
        ) = _calculateFeesOutGivenBondsIn(
            _bondAmount,
            _timeRemaining,
            spotPrice,
            _sharePrice
        );

        // ShareReservesDelta is the number of shares to remove from the shareReserves and
        // since the totalCurveFee includes the totalGovernanceFee it needs to be added back
        // to so that it is removed from the shareReserves. The shareReservesDelta,
        // totalCurveFee and totalGovernanceFee are all in terms of shares:

        // shares -= shares - shares
        shareReservesDelta -= totalCurveFee - totalGovernanceFee;

        // The trader will need to deposit capital to pay for the fixed rate,
        // the curve fee, the flat fee, and any back-paid interest that will be
        // received back upon closing the trade.
        traderDeposit = HyperdriveMath
            .calculateShortProceeds(
                _bondAmount,
                // NOTE: We add the governance fee back to the share reserves
                // delta here because the trader will need to provide this in
                // their deposit.
                shareReservesDelta - totalGovernanceFee,
                _openSharePrice,
                _sharePrice,
                _sharePrice,
                _flatFee
            )
            .mulDown(_sharePrice);

        return (traderDeposit, shareReservesDelta, totalGovernanceFee);
    }

    /// @dev Calculate the pool reserve and trader deltas that result from
    ///      closing a short. This calculation includes trading fees.
    /// @param _bondAmount The amount of bonds being purchased to close the short.
    /// @param _sharePrice The current share price.
    /// @param _maturityTime The maturity time of the short position.
    /// @return shareReservesDelta The change in the share reserves.
    /// @return bondReservesDelta The change in the bond reserves.
    /// @return sharePayment The cost in shares of buying the bonds.
    /// @return totalGovernanceFee The governance fee in shares.
    function _calculateCloseShort(
        uint256 _bondAmount,
        uint256 _sharePrice,
        uint256 _maturityTime
    )
        internal
        returns (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 sharePayment,
            uint256 totalGovernanceFee
        )
    {
        // Calculate the effect that closing the short should have on the pool's
        // reserves as well as the amount of shares the trader needs to pay to
        // purchase the shorted bonds at the market price.
        // NOTE: We calculate the time remaining from the latest checkpoint to
        // ensure that opening/closing a position doesn't result in immediate
        // profit.
        uint256 timeRemaining = _calculateTimeRemaining(_maturityTime);
        (shareReservesDelta, bondReservesDelta, sharePayment) = HyperdriveMath
            .calculateCloseShort(
                _effectiveShareReserves(),
                _marketState.bondReserves,
                _bondAmount,
                timeRemaining,
                _timeStretch,
                _sharePrice,
                _initialSharePrice
            );

        // Calculate the fees charged on the curve and flat parts of the trade.
        // Since we calculate the amount of shares paid given bonds out, we add
        // the fee from the share deltas so that the trader pays less shares.
        uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
            _effectiveShareReserves(),
            _marketState.bondReserves,
            _initialSharePrice,
            _timeStretch
        );

        // Record an oracle update
        recordPrice(spotPrice);

        // Calculate the fees charged to the user (totalCurveFee and totalFlatFee)
        // and the portion of those fees that are paid to governance
        // (governanceCurveFee and governanceFlatFee).
        (
            uint256 totalCurveFee,
            uint256 totalFlatFee,
            uint256 governanceCurveFee,
            uint256 governanceFlatFee
        ) = _calculateFeesInGivenBondsOut(
                _bondAmount,
                timeRemaining,
                spotPrice,
                _sharePrice
            );

        // Add the total curve fee minus the governance curve fee to the amount that will
        // be added to the share reserves. This ensures that the LPs are credited with the
        // fee the trader paid on the curve trade minus the portion of the curve fee that
        // was paid to governance.
        // shareReservesDelta, totalGovernanceFee and governanceCurveFee
        // are all denominated in shares so we just need to subtract out
        // the governanceCurveFees from the shareReservesDelta since that
        // fee isn't reserved for the LPs
        // shares += shares - shares
        shareReservesDelta += totalCurveFee - governanceCurveFee;

        // Calculate the sharePayment that the user must make to close out
        // the short. We add the totalCurveFee (shares) and totalFlatFee (shares)
        // to the sharePayment to ensure that fees are collected.
        // shares += shares + shares
        sharePayment += totalCurveFee + totalFlatFee;

        return (
            shareReservesDelta,
            bondReservesDelta,
            sharePayment,
            governanceCurveFee + governanceFlatFee
        );
    }
}
