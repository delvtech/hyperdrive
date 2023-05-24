// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { HyperdriveLP } from "./HyperdriveLP.sol";
import { AssetId } from "./libraries/AssetId.sol";
import { Errors } from "./libraries/Errors.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { HyperdriveMath } from "./libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "./libraries/YieldSpaceMath.sol";

/// @author DELV
/// @title HyperdriveShort
/// @notice Implements the short accounting for Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveShort is HyperdriveLP {
    using FixedPointMath for uint256;
    using SafeCast for uint256;

    /// @notice Opens a short position.
    /// @param _bondAmount The amount of bonds to short.
    /// @param _maxDeposit The most the user expects to deposit for this trade
    /// @param _destination The address which gets credited with share tokens
    /// @param _asUnderlying If true the user is charged in underlying if false
    ///                      the contract transfers in yield source directly.
    ///                      Note - for some paths one choice may be disabled or blocked.
    /// @return The amount the user deposited for this trade
    function openShort(
        uint256 _bondAmount,
        uint256 _maxDeposit,
        address _destination,
        bool _asUnderlying
    ) external isNotPaused returns (uint256) {
        if (_bondAmount == 0) {
            revert Errors.ZeroAmount();
        }

        // Perform a checkpoint and compute the amount of interest the short
        // would have received if they opened at the beginning of the checkpoint.
        // Since the short will receive interest from the beginning of the
        // checkpoint, they will receive this backdated interest back at closing.
        uint256 sharePrice = _pricePerShare();
        uint256 openSharePrice = _applyCheckpoint(
            _latestCheckpoint(),
            sharePrice
        );

        // Calculate the pool and user deltas using the trading function. We
        // backdate the bonds sold to the beginning of the checkpoint.
        uint256 maturityTime = _latestCheckpoint() + _positionDuration;
        uint256 timeRemaining = _calculateTimeRemaining(maturityTime);
        uint256 shareReservesDelta;
        {
            uint256 totalGovernanceFee;
            (shareReservesDelta, totalGovernanceFee) = _calculateOpenShort(
                _bondAmount,
                sharePrice,
                timeRemaining
            );

            // Attribute the governance fees.
            _governanceFeesAccrued += totalGovernanceFee;
        }

        // Take custody of the trader's deposit and ensure that the trader
        // doesn't pay more than their max deposit. The trader's deposit is
        // equal to the proceeds that they would receive if they closed
        // immediately (without fees).
        uint256 traderDeposit = HyperdriveMath
            .calculateShortProceeds(
                _bondAmount,
                shareReservesDelta,
                openSharePrice,
                sharePrice,
                sharePrice
            )
            .mulDown(sharePrice);
        if (_maxDeposit < traderDeposit) revert Errors.OutputLimit();
        _deposit(traderDeposit, _asUnderlying);

        // Apply the state updates caused by opening the short.
        _applyOpenShort(
            _bondAmount,
            shareReservesDelta,
            sharePrice,
            openSharePrice,
            timeRemaining,
            maturityTime
        );

        // Mint the short tokens to the trader. The ID is a concatenation of the
        // current share price and the maturity time of the shorts.
        _mint(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, maturityTime),
            _destination,
            _bondAmount
        );

        // Emit an OpenShort event.
        uint256 bondAmount = _bondAmount; // Avoid stack too deep error.
        emit OpenShort(_destination, maturityTime, traderDeposit, bondAmount);

        return (traderDeposit);
    }

    /// @notice Closes a short position with a specified maturity time.
    /// @param _maturityTime The maturity time of the short.
    /// @param _bondAmount The amount of shorts to close.
    /// @param _minOutput The minimum output of this trade.
    /// @param _destination The address which gets the proceeds from closing this short
    /// @param _asUnderlying If true the user is paid in underlying if false
    ///                      the contract transfers in yield source directly.
    ///                      Note - for some paths one choice may be disabled or blocked.
    /// @return The amount of base tokens produced by closing this short
    function closeShort(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256) {
        if (_bondAmount == 0) {
            revert Errors.ZeroAmount();
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

        // Attribute the governance fees.
        _governanceFeesAccrued += totalGovernanceFee;

        // If the position hasn't matured, apply the accounting updates that
        // result from closing the short to the reserves and pay out the
        // withdrawal pool if necessary.
        if (block.timestamp < _maturityTime) {
            _applyCloseShort(
                _bondAmount,
                bondReservesDelta,
                sharePayment - totalGovernanceFee,
                shareReservesDelta,
                _maturityTime,
                sharePrice
            );
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
            sharePrice
        );
        (uint256 baseProceeds, ) = _withdraw(
            shortProceeds,
            _destination,
            _asUnderlying
        );

        // Enforce min user outputs
        if (baseProceeds < _minOutput) revert Errors.OutputLimit();

        // Emit a CloseShort event.
        uint256 maturityTime = _maturityTime; // Avoid stack too deep error.
        uint256 bondAmount = _bondAmount; // Avoid stack too deep error.
        emit CloseShort(_destination, maturityTime, baseProceeds, bondAmount);

        return baseProceeds;
    }

    /// @dev Applies an open short to the state. This includes updating the
    ///      reserves and maintaining the reserve invariants.
    /// @param _bondAmount The amount of bonds shorted.
    /// @param _shareReservesDelta The amount of shares paid to the curve.
    /// @param _sharePrice The share price.
    /// @param _openSharePrice The current checkpoint's share price.
    /// @param _maturityTime The maturity time of the long.
    /// @param _timeRemaining The time remaining until maturity.
    function _applyOpenShort(
        uint256 _bondAmount,
        uint256 _shareReservesDelta,
        uint256 _sharePrice,
        uint256 _openSharePrice,
        uint256 _timeRemaining,
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

        // Update the base volume of short positions.
        uint128 baseVolume = HyperdriveMath
            .calculateBaseVolume(
                _shareReservesDelta.mulDown(_openSharePrice),
                _bondAmount,
                _timeRemaining
            )
            .toUint128();
        _marketState.shortBaseVolume += baseVolume;
        _checkpoints[_latestCheckpoint()].shortBaseVolume += baseVolume;

        // Apply the trading deltas to the reserves and increase the bond buffer
        // by the amount of bonds that were shorted. We don't need to add the
        // margin or pre-paid interest to the reserves because of the way that
        // the close short accounting works.
        _marketState.shareReserves -= _shareReservesDelta.toUint128();
        _marketState.bondReserves += _bondAmount.toUint128();
        _marketState.shortsOutstanding += _bondAmount.toUint128();

        // Since the share reserves are reduced, we need to verify that the base
        // reserves are greater than or equal to the amount of longs outstanding.
        if (
            _sharePrice.mulDown(_marketState.shareReserves) <
            _marketState.longsOutstanding
        ) {
            revert Errors.BaseBufferExceedsShareReserves();
        }
    }

    /// @dev Applies the trading deltas from a closed short to the reserves and
    ///      the withdrawal pool.
    /// @param _bondAmount The amount of shorts that were closed.
    /// @param _bondReservesDelta The amount of bonds paid by the curve.
    /// @param _sharePayment The payment in shares required to close the short.
    /// @param _shareReservesDelta The amount of bonds paid to the curve.
    /// @param _maturityTime The maturity time of the short.
    /// @param _sharePrice The current share price
    function _applyCloseShort(
        uint256 _bondAmount,
        uint256 _bondReservesDelta,
        uint256 _sharePayment,
        uint256 _shareReservesDelta,
        uint256 _maturityTime,
        uint256 _sharePrice
    ) internal {
        // Update the short average maturity time.
        _marketState.shortAverageMaturityTime = uint256(
            _marketState.shortAverageMaturityTime
        )
            .updateWeightedAverage(
                _marketState.shortsOutstanding,
                _maturityTime * 1e18, // scale up to fixed point scale
                _bondAmount,
                false
            )
            .toUint128();

        // Update the base volume aggregates.
        {
            // Get the total supply of shorts in the checkpoint of the shorts
            // being closed. If the shorts are closed before maturity, we add the
            // amount of shorts being closed since the total supply is decreased
            // when burning the short tokens.
            uint256 checkpointAmount = _totalSupply[
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    _maturityTime
                )
            ];
            if (block.timestamp < _maturityTime) {
                checkpointAmount += _bondAmount;
            }

            // Remove a proportional amount of the checkpoints base volume from
            // the aggregates.
            uint256 checkpointTime = _maturityTime - _positionDuration;
            uint128 proportionalBaseVolume = uint256(
                _checkpoints[checkpointTime].shortBaseVolume
            ).mulDown(_bondAmount.divDown(checkpointAmount)).toUint128();
            _marketState.shortBaseVolume -= proportionalBaseVolume;
            _checkpoints[checkpointTime]
                .shortBaseVolume -= proportionalBaseVolume;
        }

        // Decrease the amount of shorts outstanding.
        _marketState.shortsOutstanding -= _bondAmount.toUint128();

        // Apply the updates from the curve trade to the reserves.
        _marketState.shareReserves += _shareReservesDelta.toUint128();
        _marketState.bondReserves -= _bondReservesDelta.toUint128();

        // Add the flat part of the trade to the pool's liquidity. We add to
        // the pool's liquidity because the LPs have a long position and thus
        // receive their principal and some fixed interest along with any
        // trading profits that have accrued.
        _updateLiquidity(int256(_sharePayment - _shareReservesDelta));

        // If there are withdrawal shares outstanding, we pay out the maximum
        // amount of withdrawal shares. The proceeds owed to LPs when a long is
        // closed is equivalent to short proceeds as LPs take the other side of
        // every trade.
        uint256 withdrawalSharesOutstanding = _totalSupply[
            AssetId._WITHDRAWAL_SHARE_ASSET_ID
        ] - _withdrawPool.readyToWithdraw;
        if (withdrawalSharesOutstanding > 0) {
            _applyWithdrawalProceeds(
                _sharePayment,
                withdrawalSharesOutstanding,
                _sharePrice
            );
        }
    }

    /// @dev Calculate the pool reserve and trader deltas that result from
    ///      opening a short. This calculation includes trading fees.
    /// @param _bondAmount The amount of bonds being sold to open the short.
    /// @param _sharePrice The current share price.
    /// @param _timeRemaining The time remaining in the position.
    /// @return shareReservesDelta The change in the share reserves.
    /// @return totalGovernanceFee The governance fee in shares.
    function _calculateOpenShort(
        uint256 _bondAmount,
        uint256 _sharePrice,
        uint256 _timeRemaining
    )
        internal
        returns (uint256 shareReservesDelta, uint256 totalGovernanceFee)
    {
        // Calculate the effect that opening the short should have on the pool's
        // reserves as well as the amount of shares the trader receives from
        // selling the shorted bonds at the market price.
        shareReservesDelta = HyperdriveMath.calculateOpenShort(
            _marketState.shareReserves,
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
            revert Errors.NegativeInterest();

        // Calculate the fees charged on the curve and flat parts of the trade.
        // Since we calculate the amount of shares received given bonds in, we
        // subtract the fee from the share deltas so that the trader receives
        // less shares.
        uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
            _marketState.shareReserves,
            _marketState.bondReserves,
            _initialSharePrice,
            _timeRemaining,
            _timeStretch
        );
        // Add the spot price to the oracle if an oracle update is required
        recordPrice(spotPrice);

        uint256 totalCurveFee;
        (
            totalCurveFee, // there is no flat fee on opening shorts
            ,
            totalGovernanceFee
        ) = _calculateFeesOutGivenBondsIn(
            _bondAmount, // amountIn
            _timeRemaining,
            spotPrice,
            _sharePrice
        );
        shareReservesDelta -= totalCurveFee;
        return (shareReservesDelta, totalGovernanceFee);
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
        // NOTE: We calculate the time remaining from the latest checkpoint to ensure that
        // opening/closing a position doesn't result in immediate profit.
        uint256 timeRemaining = _calculateTimeRemaining(_maturityTime);
        (shareReservesDelta, bondReservesDelta, sharePayment) = HyperdriveMath
            .calculateCloseShort(
                _marketState.shareReserves,
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
        uint256 spotPrice = _marketState.bondReserves > 0
            ? HyperdriveMath.calculateSpotPrice(
                _marketState.shareReserves,
                _marketState.bondReserves,
                _initialSharePrice,
                timeRemaining,
                _timeStretch
            )
            : FixedPointMath.ONE_18;

        // Record an oracle update
        recordPrice(spotPrice);

        (
            uint256 totalCurveFee,
            uint256 totalFlatFee,
            uint256 governanceCurveFee,
            uint256 governanceFlatFee
        ) = _calculateFeesInGivenBondsOut(
                _bondAmount, // amountOut
                timeRemaining,
                spotPrice,
                _sharePrice
            );
        shareReservesDelta += totalCurveFee - governanceCurveFee;
        sharePayment += totalCurveFee + totalFlatFee;

        return (
            shareReservesDelta,
            bondReservesDelta,
            sharePayment,
            governanceCurveFee + governanceFlatFee
        );
    }
}
