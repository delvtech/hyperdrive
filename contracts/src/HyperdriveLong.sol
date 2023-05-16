// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { HyperdriveLP } from "./HyperdriveLP.sol";
import { AssetId } from "./libraries/AssetId.sol";
import { Errors } from "./libraries/Errors.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { HyperdriveMath } from "./libraries/HyperdriveMath.sol";
import "forge-std/console2.sol";

/// @author DELV
/// @title HyperdriveLong
/// @notice Implements the long accounting for Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveLong is HyperdriveLP {
    using FixedPointMath for uint256;
    using SafeCast for uint256;

    /// @notice Opens a long position.
    /// @param _baseAmount The amount of base to use when trading.
    /// @param _minOutput The minium number of bonds to receive.
    /// @param _destination The address which will receive the bonds
    /// @param _asUnderlying If true the user is charged in underlying if false
    ///                      the contract transfers in yield source directly.
    ///                      Note - for some paths one choice may be disabled or blocked.
    /// @return The number of bonds the user received
    function openLong(
        uint256 _baseAmount,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external isNotPaused returns (uint256) {
        if (_baseAmount == 0) {
            revert Errors.ZeroAmount();
        }

        // Deposit the user's base.
        (uint256 shares, uint256 sharePrice) = _deposit(
            _baseAmount,
            _asUnderlying
        );

        // Perform a checkpoint.
        uint256 latestCheckpoint = _latestCheckpoint();
        _applyCheckpoint(latestCheckpoint, sharePrice);

        // Calculate the pool and user deltas using the trading function. We
        // backdate the bonds purchased to the beginning of the checkpoint.
        uint256 maturityTime = latestCheckpoint + _positionDuration;
        uint256 timeRemaining = _calculateTimeRemaining(maturityTime);
        (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 bondProceeds,
            uint256 totalGovernanceFee
        ) = _calculateOpenLong(shares, sharePrice, timeRemaining);

        // If the user gets less bonds than they paid, we are in the negative
        // interest region of the trading function.
        if (bondProceeds < _baseAmount) revert Errors.NegativeInterest();

        // Enforce min user outputs
        if (_minOutput > bondProceeds) revert Errors.OutputLimit();

        // Attribute the governance fee.
        _governanceFeesAccrued += totalGovernanceFee;

        // Apply the open long to the state.
        _applyOpenLong(
            _baseAmount - totalGovernanceFee,
            shareReservesDelta,
            bondProceeds,
            bondReservesDelta,
            sharePrice,
            latestCheckpoint,
            maturityTime
        );

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
    /// @param _asUnderlying If true the user is paid in underlying if false
    ///                      the contract transfers in yield source directly.
    ///                      Note - for some paths one choice may be disabled or blocked.
    /// @return The amount of underlying the user receives.
    function closeLong(
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        address _destination,
        bool _asUnderlying
    ) external returns (uint256) {
        if (_bondAmount == 0) {
            revert Errors.ZeroAmount();
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
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 shareProceeds,
            uint256 totalGovernanceFee
        ) = _calculateCloseLong(_bondAmount, sharePrice, _maturityTime);

        // Attribute the governance fee.
        _governanceFeesAccrued += totalGovernanceFee;

        // If the position hasn't matured, apply the accounting updates that
        // result from closing the long to the reserves and pay out the
        // withdrawal pool if necessary.
        if (block.timestamp < _maturityTime) {
            _applyCloseLong(
                _bondAmount,
                bondReservesDelta,
                shareProceeds,
                shareReservesDelta,
                _maturityTime,
                sharePrice
            );
        }

        // Withdraw the profit to the trader.
        (uint256 baseProceeds, ) = _withdraw(
            shareProceeds,
            _destination,
            _asUnderlying
        );

        // Enforce min user outputs
        if (_minOutput > baseProceeds) revert Errors.OutputLimit();

        return (baseProceeds);
    }

    /// @dev Applies an open long to the state. This includes updating the
    ///      reserves and maintaining the reserve invariants.
    /// @param _baseAmount The amount of base paid by the trader.
    /// @param _shareReservesDelta The amount of shares paid to the curve.
    /// @param _bondProceeds The amount of bonds purchased by the trader.
    /// @param _bondReservesDelta The amount of bonds sold by the curve.
    /// @param _sharePrice The share price.
    /// @param _checkpointTime The time of the latest checkpoint.
    /// @param _maturityTime The maturity time of the long.
    function _applyOpenLong(
        uint256 _baseAmount,
        uint256 _shareReservesDelta,
        uint256 _bondProceeds,
        uint256 _bondReservesDelta,
        uint256 _sharePrice,
        uint256 _checkpointTime,
        uint256 _maturityTime
    ) internal {
        // Update the average maturity time of long positions.
        _marketState.longAverageMaturityTime = uint256(
            _marketState.longAverageMaturityTime
        )
            .updateWeightedAverage(
                uint256(_marketState.longsOutstanding),
                _maturityTime * 1e18, // scale up to fixed point scale
                _bondProceeds,
                true
            )
            .toUint128();

        // Update the long share price of the checkpoint and the global long
        // open share price.
        _checkpoints[_checkpointTime].longSharePrice = uint256(
            _checkpoints[_checkpointTime].longSharePrice
        )
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
                uint256(_marketState.longsOutstanding),
                _sharePrice,
                _bondProceeds,
                true
            )
            .toUint128();

        // Apply the trading deltas to the reserves and update the amount of
        // longs outstanding.
        _marketState.shareReserves += _shareReservesDelta.toUint128();
        _marketState.bondReserves -= _bondReservesDelta.toUint128();
        _marketState.longsOutstanding += _bondProceeds.toUint128();

        // Add the flat component of the trade to the pool's liquidity.
        _updateLiquidity(
            int256(_baseAmount.divDown(_sharePrice) - _shareReservesDelta)
        );

        // Since the base buffer may have increased relative to the base
        // reserves and the bond reserves decreased, we must ensure that the
        // base reserves are greater than the longsOutstanding.
        if (
            _sharePrice.mulDown(uint256(_marketState.shareReserves)) <
            _marketState.longsOutstanding
        ) {
            revert Errors.BaseBufferExceedsShareReserves();
        }
    }

    /// @dev Applies the trading deltas from a closed long to the reserves and
    ///      the withdrawal pool.
    /// @param _bondAmount The amount of longs that were closed.
    /// @param _bondReservesDelta The bonds paid to the curve.
    /// @param _shareProceeds The proceeds received from closing the long.
    /// @param _shareReservesDelta The shares paid by the curve.
    /// @param _maturityTime The maturity time of the long.
    /// @param _sharePrice The current price of shares
    function _applyCloseLong(
        uint256 _bondAmount,
        uint256 _bondReservesDelta,
        uint256 _shareProceeds,
        uint256 _shareReservesDelta,
        uint256 _maturityTime,
        uint256 _sharePrice
    ) internal {
        // Update the long average maturity time.
        _marketState.longAverageMaturityTime = uint256(
            _marketState.longAverageMaturityTime
        )
            .updateWeightedAverage(
                _marketState.longsOutstanding,
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
                _marketState.longsOutstanding,
                _checkpoints[_maturityTime - _positionDuration].longSharePrice,
                _bondAmount,
                false
            )
            .toUint128();

        // Reduce the amount of outstanding longs.
        _marketState.longsOutstanding -= _bondAmount.toUint128();

        // Apply the updates from the curve trade to the reserves.
        _marketState.shareReserves -= _shareReservesDelta.toUint128();
        _marketState.bondReserves += _bondReservesDelta.toUint128();

        // Remove the flat part of the trade from the pool's liquidity.
        _updateLiquidity(-int256(_shareProceeds - _shareReservesDelta));

        // If there are withdrawal shares outstanding, we pay out the maximum
        // amount of withdrawal shares. The proceeds owed to LPs when a long is
        // closed is equivalent to short proceeds as LPs take the other side of
        // every trade.
        uint256 withdrawalSharesOutstanding = _totalSupply[
            AssetId._WITHDRAWAL_SHARE_ASSET_ID
        ] - _withdrawPool.readyToWithdraw;
        if (withdrawalSharesOutstanding > 0) {
            uint256 openSharePrice = _checkpoints[
                _maturityTime - _positionDuration
            ].longSharePrice;
            uint256 withdrawalProceeds = HyperdriveMath.calculateShortProceeds(
                _bondAmount,
                _shareProceeds,
                openSharePrice,
                _sharePrice,
                _sharePrice
            );
            _applyWithdrawalProceeds(
                withdrawalProceeds,
                withdrawalSharesOutstanding,
                _sharePrice
            );
        }
    }

    /// @dev Calculate the pool reserve and trader deltas that result from
    ///      opening a long. This calculation includes trading fees.
    /// @param _shareAmount The amount of shares being paid to open the long.
    /// @param _sharePrice The current share price.
    /// @param _timeRemaining The time remaining in the position.
    /// @return shareReservesDelta The change in the share reserves.
    /// @return bondReservesDelta The change in the bond reserves.
    /// @return bondProceeds The proceeds in bonds.
    /// @return totalGovernanceFee The governance fee in shares.
    function _calculateOpenLong(
        uint256 _shareAmount,
        uint256 _sharePrice,
        uint256 _timeRemaining
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
        (shareReservesDelta, bondReservesDelta, bondProceeds) = HyperdriveMath
            .calculateOpenLong(
                _marketState.shareReserves,
                _marketState.bondReserves,
                _shareAmount, // amountIn
                _timeRemaining,
                _timeStretch,
                _sharePrice,
                _initialSharePrice
            );

        // Calculate the fees charged on the curve and flat parts of the trade.
        // Since we calculate the amount of bonds received given shares in, we
        // subtract the fee from the bond deltas so that the trader receives
        // less bonds.
        uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
            _marketState.shareReserves,
            _marketState.bondReserves,
            _initialSharePrice,
            _timeRemaining,
            _timeStretch
        );

        // Record an oracle update
        recordPrice(spotPrice);

        (
            uint256 totalCurveFee,
            uint256 totalFlatFee,
            uint256 governanceCurveFee,
            uint256 governanceFlatFee
        ) = _calculateFeesOutGivenSharesIn(
                _shareAmount, // amountIn
                bondProceeds, // amountOut
                _timeRemaining,
                spotPrice,
                _sharePrice
            );
        bondReservesDelta -= totalCurveFee - governanceCurveFee;
        bondProceeds -= totalCurveFee + totalFlatFee;

        // Calculate the fees owed to governance in shares.
        shareReservesDelta -= governanceCurveFee.divDown(_sharePrice);
        totalGovernanceFee = (governanceCurveFee + governanceFlatFee).divDown(
            _sharePrice
        );

        return (
            shareReservesDelta,
            bondReservesDelta,
            bondProceeds,
            totalGovernanceFee
        );
    }

    /// @dev Calculate the pool reserve and trader deltas that result from
    ///      closing a long. This calculation includes trading fees.
    /// @param _bondAmount The amount of bonds being purchased to close the short.
    /// @param _sharePrice The current share price.
    /// @param _maturityTime The maturity time of the short position.
    /// @return shareReservesDelta The change in the share reserves.
    /// @return bondReservesDelta The change in the bond reserves.
    /// @return shareProceeds The proceeds in shares of selling the bonds.
    /// @return totalGovernanceFee The governance fee in shares.
    function _calculateCloseLong(
        uint256 _bondAmount,
        uint256 _sharePrice,
        uint256 _maturityTime
    )
        internal
        returns (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 shareProceeds,
            uint256 totalGovernanceFee
        )
    {
        // Calculate the effect that closing the long should have on the pool's
        // reserves as well as the amount of shares the trader receives for
        // selling the bonds at the market price.
        uint256 timeRemaining = _calculateTimeRemaining(_maturityTime);
        uint256 closeSharePrice = block.timestamp < _maturityTime
            ? _sharePrice
            : _checkpoints[_maturityTime].sharePrice;
        (shareReservesDelta, bondReservesDelta, shareProceeds) = HyperdriveMath
            .calculateCloseLong(
                _marketState.shareReserves,
                _marketState.bondReserves,
                _bondAmount,
                timeRemaining,
                _timeStretch,
                closeSharePrice,
                _sharePrice,
                _initialSharePrice
            );

        // Calculate the fees charged on the curve and flat parts of the trade.
        // Since we calculate the amount of shares received given bonds in, we
        // subtract the fee from the share deltas so that the trader receives
        // less shares.
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

        uint256 totalCurveFee;
        uint256 totalFlatFee;
        (
            totalCurveFee,
            totalFlatFee,
            totalGovernanceFee
        ) = _calculateFeesOutGivenBondsIn(
            _bondAmount, // amountIn
            timeRemaining,
            spotPrice,
            _sharePrice
        );
        shareReservesDelta -= totalCurveFee;
        shareProceeds -= totalCurveFee + totalFlatFee;

        return (
            shareReservesDelta,
            bondReservesDelta,
            shareProceeds,
            totalGovernanceFee
        );
    }
}
