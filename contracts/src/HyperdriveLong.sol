// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveLP } from "./HyperdriveLP.sol";
import { IHyperdrive } from "./interfaces/IHyperdrive.sol";
import { AssetId } from "./libraries/AssetId.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { HyperdriveMath } from "./libraries/HyperdriveMath.sol";
import { SafeCast } from "./libraries/SafeCast.sol";

/// @author DELV
/// @title HyperdriveLong
/// @notice Implements the long accounting for Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveLong is HyperdriveLP {
    using FixedPointMath for uint256;
    using FixedPointMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;

    /// @notice Opens a long position.
    /// @param _baseAmount The amount of base to use when trading.
    /// @param _minOutput The minium number of bonds to receive.
    /// @param _minSharePrice The minium share price at which to open the long.
    ///        This allows traders to protect themselves from opening a long in
    ///        a checkpoint where negative interest has accrued.
    /// @param _destination The address which will receive the bonds
    /// @param _asUnderlying A flag indicating whether the sender will pay in
    ///        base or using another currency. Implementations choose which
    ///        currencies they accept.
    /// @param _extraData The extra data to provide to the yield source.
    /// @return maturityTime The maturity time of the bonds.
    /// @return bondProceeds The amount of bonds the user received
    function openLong(
        uint256 _baseAmount,
        uint256 _minOutput,
        uint256 _minSharePrice,
        address _destination,
        bool _asUnderlying,
        bytes memory _extraData
    )
        external
        payable
        nonReentrant
        isNotPaused
        returns (uint256 maturityTime, uint256 bondProceeds)
    {
        // Check that the message value and base amount are valid.
        _checkMessageValue();
        if (_baseAmount < _minimumTransactionAmount) {
            revert IHyperdrive.MinimumTransactionAmount();
        }

        // Deposit the user's base.
        (uint256 shares, uint256 sharePrice) = _deposit(
            _baseAmount,
            _asUnderlying,
            _extraData
        );
        if (sharePrice < _minSharePrice) {
            revert IHyperdrive.MinimumSharePrice();
        }

        // Perform a checkpoint.
        uint256 latestCheckpoint = _latestCheckpoint();
        _applyCheckpoint(latestCheckpoint, sharePrice);

        // Calculate the pool and user deltas using the trading function. We
        // backdate the bonds purchased to the beginning of the checkpoint.
        uint256 shareReservesDelta;
        uint256 bondReservesDelta;
        uint256 totalGovernanceFee;
        (
            shareReservesDelta,
            bondReservesDelta,
            bondProceeds,
            totalGovernanceFee
        ) = _calculateOpenLong(shares, sharePrice);

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

        // Enforce min user outputs
        if (_minOutput > bondProceeds) revert IHyperdrive.OutputLimit();

        // Attribute the governance fee.
        _governanceFeesAccrued += totalGovernanceFee;

        // Apply the open long to the state.
        maturityTime = latestCheckpoint + _positionDuration;
        _applyOpenLong(
            shareReservesDelta,
            bondProceeds,
            bondReservesDelta,
            sharePrice,
            latestCheckpoint,
            maturityTime
        );

        // Mint the bonds to the trader with an ID of the maturity time.
        uint256 assetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            maturityTime
        );
        _mint(assetId, _destination, bondProceeds);

        // Emit an OpenLong event.
        uint256 baseAmount = _baseAmount; // Avoid stack too deep error.
        emit OpenLong(
            _destination,
            assetId,
            maturityTime,
            baseAmount,
            bondProceeds
        );

        return (maturityTime, bondProceeds);
    }

    /// @notice Closes a long position with a specified maturity time.
    /// @param _maturityTime The maturity time of the short.
    /// @param _bondAmount The amount of longs to close.
    /// @param _minOutput The minimum base the user should receive from this trade
    /// @param _destination The address which will receive the proceeds of this sale
    /// @param _asUnderlying A flag indicating whether the sender will pay in
    ///        base or using another currency. Implementations choose which
    ///        currencies they accept.
    /// @param _extraData The extra data to provide to the yield source.
    /// @return The amount of underlying the user receives.
    function closeLong(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying,
        bytes memory _extraData
    ) external nonReentrant returns (uint256) {
        if (_bondAmount < _minimumTransactionAmount) {
            revert IHyperdrive.MinimumTransactionAmount();
        }

        // Perform a checkpoint at the maturity time. This ensures the long and
        // all of the other positions in the checkpoint are closed. This will
        // have no effect if the maturity time is in the future.
        uint256 sharePrice = _pricePerShare();
        _applyCheckpoint(_maturityTime, sharePrice);

        // Burn the longs that are being closed.
        _burn(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, _maturityTime),
            msg.sender,
            _bondAmount
        );

        // Calculate the pool and user deltas using the trading function.
        (
            uint256 sharePayment,
            uint256 shareProceeds,
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 totalGovernanceFee
        ) = _calculateCloseLong(_bondAmount, sharePrice, _maturityTime);

        // If the position hasn't matured, apply the accounting updates that
        // result from closing the long to the reserves and pay out the
        // withdrawal pool if necessary.
        uint256 maturityTime = _maturityTime; // Avoid stack too deep error.
        if (block.timestamp < _maturityTime) {
            // Attribute the governance fee.
            _governanceFeesAccrued += totalGovernanceFee;
            _applyCloseLong(
                _bondAmount,
                bondReservesDelta,
                sharePayment,
                shareReservesDelta,
                maturityTime
            );

            // Update the checkpoint and global longExposure
            uint256 checkpointTime = maturityTime - _positionDuration;
            int128 checkpointExposureBefore = int128(
                _checkpoints[checkpointTime].longExposure
            );
            _updateCheckpointLongExposureOnClose(
                _bondAmount,
                shareReservesDelta,
                bondReservesDelta,
                sharePayment,
                maturityTime,
                sharePrice,
                true
            );
            _updateLongExposure(
                checkpointExposureBefore,
                _checkpoints[checkpointTime].longExposure
            );

            // Distribute the excess idle to the withdrawal pool.
            _distributeExcessIdle(sharePrice);
        }

        // Withdraw the profit to the trader.
        uint256 baseProceeds = _withdraw(
            shareProceeds,
            _destination,
            _asUnderlying,
            _extraData
        );

        // Enforce min user outputs
        if (_minOutput > baseProceeds) revert IHyperdrive.OutputLimit();

        // Emit a CloseLong event.
        uint256 bondAmount = _bondAmount; // Avoid stack too deep error.
        emit CloseLong(
            _destination,
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            maturityTime,
            baseProceeds,
            bondAmount
        );

        return (baseProceeds);
    }

    /// @dev Applies an open long to the state. This includes updating the
    ///      reserves and maintaining the reserve invariants.
    /// @param _shareReservesDelta The amount of shares paid to the curve.
    /// @param _bondProceeds The amount of bonds purchased by the trader.
    /// @param _bondReservesDelta The amount of bonds sold by the curve.
    /// @param _sharePrice The share price.
    /// @param _checkpointTime The time of the latest checkpoint.
    /// @param _maturityTime The maturity time of the long.
    function _applyOpenLong(
        uint256 _shareReservesDelta,
        uint256 _bondProceeds,
        uint256 _bondReservesDelta,
        uint256 _sharePrice,
        uint256 _checkpointTime,
        uint256 _maturityTime
    ) internal {
        uint128 longsOutstanding_ = _marketState.longsOutstanding;
        // Update the average maturity time of long positions.
        _marketState.longAverageMaturityTime = uint256(
            _marketState.longAverageMaturityTime
        )
            .updateWeightedAverage(
                uint256(longsOutstanding_),
                _maturityTime * 1e18, // scale up to fixed point scale
                _bondProceeds,
                true
            )
            .toUint128();

        // Update the long share price of the checkpoint and the global long
        // open share price.
        IHyperdrive.Checkpoint storage checkpoint = _checkpoints[
            _checkpointTime
        ];
        checkpoint.longSharePrice = uint256(checkpoint.longSharePrice)
            .updateWeightedAverage(
                uint256(
                    _totalSupply[
                        AssetId.encodeAssetId(
                            AssetId.AssetIdPrefix.Long,
                            _maturityTime
                        )
                    ]
                ),
                _sharePrice,
                _bondProceeds,
                true
            )
            .toUint128();
        _marketState.longOpenSharePrice = uint256(
            _marketState.longOpenSharePrice
        )
            .updateWeightedAverage(
                uint256(longsOutstanding_),
                _sharePrice,
                _bondProceeds,
                true
            )
            .toUint128();

        // Apply the trading deltas to the reserves and update the amount of
        // longs outstanding.
        _marketState.shareReserves += _shareReservesDelta.toUint128();
        _marketState.bondReserves -= _bondReservesDelta.toUint128();
        longsOutstanding_ += _bondProceeds.toUint128();
        _marketState.longsOutstanding = longsOutstanding_;

        // Increase the exposure by the amount the LPs must reserve to cover the
        // long. We are overly conservative, so this is equal to the amount of
        // fixed interest the long is owed at maturity plus the face value of
        // the long.
        int128 checkpointExposureBefore = int128(checkpoint.longExposure);
        uint128 longExposureDelta = (2 *
            _bondProceeds -
            _shareReservesDelta.mulDown(_sharePrice)).toUint128();
        checkpoint.longExposure += int128(longExposureDelta);
        _updateLongExposure(checkpointExposureBefore, checkpoint.longExposure);

        // We need to check solvency because longs increase the system's exposure.
        if (!_isSolvent(_sharePrice)) {
            revert IHyperdrive.BaseBufferExceedsShareReserves();
        }

        // Distribute the excess idle to the withdrawal pool.
        _distributeExcessIdle(_sharePrice);
    }

    /// @dev Applies the trading deltas from a closed long to the reserves and
    ///      the withdrawal pool.
    /// @param _bondAmount The amount of longs that were closed.
    /// @param _bondReservesDelta The bonds paid to the curve.
    /// @param _shareProceeds The proceeds received from closing the long.
    /// @param _shareReservesDelta The shares paid by the curve.
    /// @param _maturityTime The maturity time of the long.
    function _applyCloseLong(
        uint256 _bondAmount,
        uint256 _bondReservesDelta,
        uint256 _shareProceeds,
        uint256 _shareReservesDelta,
        uint256 _maturityTime
    ) internal {
        {
            uint128 longsOutstanding_ = _marketState.longsOutstanding;

            // Update the long average maturity time.
            _marketState.longAverageMaturityTime = uint256(
                _marketState.longAverageMaturityTime
            )
                .updateWeightedAverage(
                    longsOutstanding_,
                    _maturityTime * 1e18, // scale up to fixed point scale
                    _bondAmount,
                    false
                )
                .toUint128();

            // Update the global long open share price.
            _marketState.longOpenSharePrice = uint256(
                _marketState.longOpenSharePrice
            )
                .updateWeightedAverage(
                    longsOutstanding_,
                    _checkpoints[_maturityTime - _positionDuration]
                        .longSharePrice,
                    _bondAmount,
                    false
                )
                .toUint128();

            // Reduce the amount of outstanding longs.
            _marketState.longsOutstanding =
                longsOutstanding_ -
                _bondAmount.toUint128();
        }

        // Apply the updates from the curve and flat components of the trade to
        // the reserves. The share proceeds are added to the share reserves
        // since the LPs are buying bonds for shares.  The bond reserves are
        // increased by the curve component to decrease the spot price. The
        // share adjustment is increased by the flat component of the share
        // reserves update so that we can translate the curve to hold the
        // pricing invariant under the flat update.
        _marketState.shareReserves -= _shareProceeds.toUint128();
        _marketState.shareAdjustment -= int256(
            _shareProceeds - _shareReservesDelta
        ).toInt128();
        _marketState.bondReserves += _bondReservesDelta.toUint128();

        // TODO: We're not sure what causes the z >= zeta check to fail.
        // It may be unnecessary, but that needs to be proven before we can
        // remove it.
        //
        // The share reserves are decreased in this operation, so we need to
        // verify that our invariants that z >= z_min and z >= zeta
        // are satisfied.
        if (
            uint256(_marketState.shareReserves) < _minimumShareReserves ||
            int256(uint256(_marketState.shareReserves)) <
            _marketState.shareAdjustment
        ) {
            revert IHyperdrive.InvalidShareReserves();
        }
    }

    /// @dev Calculate the pool reserve and trader deltas that result from
    ///      opening a long. This calculation includes trading fees.
    /// @param _shareAmount The amount of shares being paid to open the long.
    /// @param _sharePrice The current share price.
    /// @return shareReservesDelta The change in the share reserves.
    /// @return bondReservesDelta The change in the bond reserves.
    /// @return bondProceeds The proceeds in bonds.
    /// @return totalGovernanceFee The governance fee in shares.
    function _calculateOpenLong(
        uint256 _shareAmount,
        uint256 _sharePrice
    )
        internal
        returns (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 bondProceeds,
            uint256 totalGovernanceFee
        )
    {
        // Calculate the effect that opening the long should have on the pool's
        // reserves as well as the amount of bond the trader receives.
        bondReservesDelta = HyperdriveMath.calculateOpenLong(
            _effectiveShareReserves(),
            _marketState.bondReserves,
            _shareAmount, // amountIn
            _timeStretch,
            _sharePrice,
            _initialSharePrice
        );

        // Calculate the fees charged on the curve and flat parts of the trade.
        // Since we calculate the amount of bonds received given shares in, we
        // subtract the fee from the bond deltas so that the trader receives
        // less bonds.
        uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
            _effectiveShareReserves(),
            _marketState.bondReserves,
            _initialSharePrice,
            _timeStretch
        );

        // Record an oracle update
        recordPrice(spotPrice);

        // Calculate the fees charged to the user (totalCurveFee) and the portion
        // of those fees that are paid to governance (governanceCurveFee).
        (
            uint256 totalCurveFee, // bonds
            uint256 governanceCurveFee // bonds
        ) = _calculateFeesOutGivenSharesIn(
                _shareAmount,
                spotPrice,
                _sharePrice
            );

        // Calculate the number of bonds the trader receives.
        // This is the amount of bonds the trader receives minus the fees.
        bondProceeds = bondReservesDelta - totalCurveFee;

        // Calculate how many bonds to remove from the bondReserves.
        // The bondReservesDelta represents how many bonds to remove
        // This should be the number of bonds the trader
        // receives plus the number of bonds we need to pay to governance.
        // In other words, we want to keep the totalCurveFee in the bondReserves; however,
        // since the governanceCurveFee will be paid from the sharesReserves we don't
        // need it removed from the bondReserves. bondProceeds and governanceCurveFee
        // are already in bonds so no conversion is needed.
        // bonds = bonds + bonds
        bondReservesDelta = bondProceeds + governanceCurveFee;

        // Calculate the fees owed to governance in shares. Open longs
        // are calculated entirely on the curve so the curve fee is the
        // total governance fee. In order to convert it to shares we need to
        // multiply it by the spot price and divide it by the share price:
        // shares = (bonds * base/bonds) / (base/shares)
        // shares = bonds * shares/bonds
        // shares = shares
        totalGovernanceFee = governanceCurveFee.mulDivDown(
            spotPrice,
            _sharePrice
        );

        // Calculate the number of shares to add to the shareReserves.
        // shareReservesDelta, _shareAmount and totalGovernanceFee
        // are all denominated in shares:
        // shares = shares - shares
        shareReservesDelta = _shareAmount - totalGovernanceFee;

        return (
            shareReservesDelta,
            bondReservesDelta,
            bondProceeds,
            totalGovernanceFee
        );
    }

    // FIXME: We should calculate the share adjustment here. There is a
    // component of the share adjustment needed for negative interest on the
    // curve and another for flat updates.
    //
    /// @dev Calculate the pool reserve and trader deltas that result from
    ///      closing a long. This calculation includes trading fees.
    /// @param _bondAmount The amount of bonds being purchased to close the short.
    /// @param _sharePrice The current share price.
    /// @param _maturityTime The maturity time of the short position.
    /// @return sharePayment The payment in shares that the LPs need to make to
    ///         ensure the trader and governance receive their proceeds.
    /// @return shareProceeds The proceeds in shares of selling the bonds.
    /// @return shareReservesDelta The change in the share reserves.
    /// @return bondReservesDelta The change in the bond reserves.
    /// @return totalGovernanceFee The governance fee in shares.
    function _calculateCloseLong(
        uint256 _bondAmount,
        uint256 _sharePrice,
        uint256 _maturityTime
    )
        internal
        returns (
            uint256 sharePayment,
            uint256 shareProceeds,
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 totalGovernanceFee
        )
    {
        // Calculate the effect that closing the long should have on the pool's
        // reserves as well as the amount of shares the trader receives for
        // selling their bonds.
        {
            // Calculate the effect that closing the long should have on the
            // pool's reserves as well as the amount of shares the trader
            // receives for selling the bonds at the market price.
            //
            // NOTE: We calculate the time remaining from the latest checkpoint
            // to ensure that opening/closing a position doesn't result in
            // immediate profit.
            uint256 timeRemaining = _calculateTimeRemaining(_maturityTime);
            (
                shareReservesDelta,
                bondReservesDelta,
                shareProceeds
            ) = HyperdriveMath.calculateCloseLong(
                _effectiveShareReserves(),
                _marketState.bondReserves,
                _bondAmount,
                timeRemaining,
                _timeStretch,
                _sharePrice,
                _initialSharePrice
            );

            // Record an oracle update.
            uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
                _effectiveShareReserves(),
                _marketState.bondReserves,
                _initialSharePrice,
                _timeStretch
            );
            recordPrice(spotPrice);

            // Calculate the fees that should be paid by the trader. The trader
            // pays a fee on the curve and flat parts of the trade. Most of the
            // fees go the LPs, but a portion goes to governance.
            uint256 totalCurveFee;
            uint256 totalFlatFee;
            (
                totalCurveFee, // shares
                totalFlatFee, // shares
                totalGovernanceFee // shares
            ) = _calculateFeesOutGivenBondsIn(
                _bondAmount,
                timeRemaining,
                spotPrice,
                _sharePrice
            );

            // The curve fee (shares) is paid to the LPs, so we subtract it from
            // the share reserves delta (shares) to prevent it from being
            // debited from the reserves when the state is updated.
            shareReservesDelta -= totalCurveFee;

            // The trader pays the curve fee (shares) and flat fee (shares) to
            // the pool, so we debit them from the trader's share proceeds
            // (shares).
            shareProceeds -= totalCurveFee + totalFlatFee;
        }

        // If negative interest accrued over the term, we scale the share
        // proceeds by the negative interest amount. Shorts should be
        // responsible for negative interest, but negative interest can exceed
        // the margin that shorts provide. This leaves us with no choice but to
        // attribute the negative interest to longs. Along with scaling the
        // share proceeds, we also scale the fee amounts.
        {
            uint256 openSharePrice = _checkpoints[
                _maturityTime - _positionDuration
            ].longSharePrice;
            uint256 closeSharePrice = block.timestamp < _maturityTime
                ? _sharePrice
                : _checkpoints[_maturityTime].sharePrice;
            if (closeSharePrice < openSharePrice) {
                shareProceeds = shareProceeds.mulDivDown(
                    closeSharePrice,
                    openSharePrice
                );
                shareReservesDelta = shareReservesDelta.mulDivDown(
                    closeSharePrice,
                    openSharePrice
                );
                totalGovernanceFee = totalGovernanceFee.mulDivDown(
                    closeSharePrice,
                    openSharePrice
                );
            }
        }

        // We applied the full curve and flat fees to the share proceeds, which
        // reduce the trader's proceeds. To calculate the payment that is
        // applied to the share reserves (and is effectively paid by the LPs),
        // we need to add governance's portion of these fees to the share
        // proceeds.
        sharePayment = shareProceeds + totalGovernanceFee;
    }
}
