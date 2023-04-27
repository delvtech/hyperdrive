// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { HyperdriveLP } from "./HyperdriveLP.sol";
import { IHyperdrive } from "./interfaces/IHyperdrive.sol";
import { AssetId } from "./libraries/AssetId.sol";
import { Copy } from "./libraries/Copy.sol";
import { Errors } from "./libraries/Errors.sol";
import { FixedPointMath } from "./libraries/FixedPointMath.sol";
import { HyperdriveMath } from "./libraries/HyperdriveMath.sol";

/// @author DELV
/// @title HyperdriveLong
/// @notice Implements the long accounting for Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveLong is HyperdriveLP {
    using Copy for IHyperdrive.PoolInfo;
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

        // FIXME: Perhaps we should make all of the variables in HyperdriveBase
        // private to avoid any use of these variables.
        //
        // FIXME: We can optimize getPoolInfo by accepting the share price to
        // avoid reloading it.
        //
        // Get the pool state and create a copy. This copy will used as an
        // in-memory state object and the updates will be applied at the end
        // of the function.
        IHyperdrive.PoolInfo memory initialPoolInfo = getPoolInfo();
        IHyperdrive.PoolInfo memory poolInfo = initialPoolInfo.copy();

        // Deposit the user's base.
        uint256 shares;
        (shares, poolInfo.sharePrice) = _deposit(_baseAmount, _asUnderlying);

        // Perform a checkpoint.
        uint256 latestCheckpoint = _latestCheckpoint();
        _applyCheckpoint(poolInfo, latestCheckpoint);

        // Calculate the pool and user deltas using the trading function. We
        // backdate the bonds purchased to the beginning of the checkpoint.
        uint256 maturityTime = latestCheckpoint + positionDuration;
        uint256 timeRemaining = _calculateTimeRemaining(maturityTime);
        (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 bondProceeds,
            uint256 totalGovernanceFee
        ) = _calculateOpenLong(poolInfo, shares, timeRemaining);

        // If the user gets less bonds than they paid, we are in the negative
        // interest region of the trading function.
        if (bondProceeds < _baseAmount) revert Errors.NegativeInterest();

        // Enforce min user outputs
        if (_minOutput > bondProceeds) revert Errors.OutputLimit();

        // Attribute the governance fee.
        governanceFeesAccrued += totalGovernanceFee;

        // Apply the open long to the temporary state.
        _applyOpenLong(
            poolInfo,
            _baseAmount - totalGovernanceFee,
            shareReservesDelta,
            bondProceeds,
            bondReservesDelta,
            latestCheckpoint,
            maturityTime,
            timeRemaining
        );

        // Update the pool's state.
        _applyStateUpdate(initialPoolInfo, poolInfo);

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

        // FIXME: We can optimize getPoolInfo by accepting the share price to
        // avoid reloading it.
        //
        // Get the pool state and create a copy. This copy will used as an
        // in-memory state object and the updates will be applied at the end
        // of the function.
        IHyperdrive.PoolInfo memory initialPoolInfo = getPoolInfo();
        IHyperdrive.PoolInfo memory poolInfo = initialPoolInfo.copy();

        // Perform a checkpoint at the maturity time. This ensures the long and
        // all of the other positions in the checkpoint are closed. This will
        // have no effect if the maturity time is in the future.
        _applyCheckpoint(poolInfo, _maturityTime);

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
        ) = _calculateCloseLong(poolInfo, _bondAmount, _maturityTime);

        // Attribute the governance fee.
        governanceFeesAccrued += totalGovernanceFee;

        // If the position hasn't matured, apply the accounting updates that
        // result from closing the long to the reserves and pay out the
        // withdrawal pool if necessary.
        if (block.timestamp < _maturityTime) {
            _applyCloseLong(
                poolInfo,
                _bondAmount,
                bondReservesDelta,
                shareProceeds,
                shareReservesDelta,
                _maturityTime
            );
        }

        // Update the pool's state.
        _applyStateUpdate(initialPoolInfo, poolInfo);

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
    /// @param _poolInfo An in-memory representation of the pool's state.
    /// @param _baseAmount The amount of base paid by the trader.
    /// @param _shareReservesDelta The amount of shares paid to the curve.
    /// @param _bondProceeds The amount of bonds purchased by the trader.
    /// @param _bondReservesDelta The amount of bonds sold by the curve.
    /// @param _checkpointTime The time of the latest checkpoint.
    /// @param _maturityTime The maturity time of the long.
    /// @param _timeRemaining The time remaining until maturity.
    function _applyOpenLong(
        IHyperdrive.PoolInfo memory _poolInfo,
        uint256 _baseAmount,
        uint256 _shareReservesDelta,
        uint256 _bondProceeds,
        uint256 _bondReservesDelta,
        uint256 _checkpointTime,
        uint256 _maturityTime,
        uint256 _timeRemaining
    ) internal {
        // Update the average maturity time of long positions.
        _poolInfo.longAverageMaturityTime = _poolInfo
            .longAverageMaturityTime
            .updateWeightedAverage(
                _poolInfo.longsOutstanding,
                _maturityTime * 1e18, // scale up to fixed point scale
                _bondProceeds,
                true
            );

        // Update the long share price of the checkpoint.
        checkpoints[_checkpointTime].longSharePrice = uint256(
            checkpoints[_checkpointTime].longSharePrice
        )
            .updateWeightedAverage(
                uint256(
                    totalSupply[
                        AssetId.encodeAssetId(
                            AssetId.AssetIdPrefix.Long,
                            _maturityTime
                        )
                    ]
                ),
                _poolInfo.sharePrice,
                _bondProceeds,
                true
            )
            .toUint128();

        // Update the base volume of long positions.
        uint256 baseVolume = HyperdriveMath.calculateBaseVolume(
            _baseAmount,
            _bondProceeds,
            _timeRemaining
        );
        _poolInfo.longBaseVolume += baseVolume;
        checkpoints[_checkpointTime].longBaseVolume += baseVolume.toUint128();

        // Apply the trading deltas to the reserves and update the amount of
        // longs outstanding.
        _poolInfo.shareReserves += _shareReservesDelta;
        _poolInfo.bondReserves -= _bondReservesDelta;
        _poolInfo.longsOutstanding += _bondProceeds;

        // Add the flat component of the trade to the pool's liquidity.
        _updateLiquidity(
            _poolInfo,
            int256(
                _baseAmount.divDown(_poolInfo.sharePrice) - _shareReservesDelta
            )
        );

        // FIXME: We need a similar check to ensure that shorts don't end up in
        // the negative interest domain.
        //
        // TODO: We should fuzz test this and other trading functions to ensure
        // that the APR never goes below zero. If it does, we may need to
        // enforce additional invariants.
        //
        // Since the base buffer may have increased relative to the base
        // reserves and the bond reserves decreased, we must ensure that the
        // base reserves are greater than the longsOutstanding.
        if (
            _poolInfo.sharePrice.mulDown(uint256(_poolInfo.shareReserves)) <
            _poolInfo.longsOutstanding
        ) {
            revert Errors.BaseBufferExceedsShareReserves();
        }
    }

    /// @dev Applies the trading deltas from a closed long to the reserves and
    ///      the withdrawal pool.
    /// @param _poolInfo An in-memory representation of the pool's state.
    /// @param _bondAmount The amount of longs that were closed.
    /// @param _bondReservesDelta The bonds paid to the curve.
    /// @param _shareProceeds The proceeds received from closing the long.
    /// @param _shareReservesDelta The shares paid by the curve.
    /// @param _maturityTime The maturity time of the long.
    function _applyCloseLong(
        IHyperdrive.PoolInfo memory _poolInfo,
        uint256 _bondAmount,
        uint256 _bondReservesDelta,
        uint256 _shareProceeds,
        uint256 _shareReservesDelta,
        uint256 _maturityTime
    ) internal {
        // Update the long average maturity time.
        _poolInfo.longAverageMaturityTime = _poolInfo
            .longAverageMaturityTime
            .updateWeightedAverage(
                _poolInfo.longsOutstanding,
                _maturityTime * 1e18, // scale up to fixed point scale
                _bondAmount,
                false
            );

        // TODO: Is it possible to abstract out the process of updating
        // aggregates in a way that is nice?
        //
        // Update the base volume aggregates, get the open share price, and
        // update the long share price of the checkpoint.
        {
            // Get the total supply of longs in the checkpoint of the longs
            // being closed. If the longs are closed before maturity, we add the
            // amount of longs being closed since the total supply is decreased
            // when burning the long tokens.
            uint256 checkpointAmount = totalSupply[
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, _maturityTime)
            ];
            if (block.timestamp < _maturityTime) {
                checkpointAmount += _bondAmount;
            }

            // Remove a proportional amount of the checkpoints base volume from
            // the aggregates.
            uint256 checkpointTime = _maturityTime - positionDuration;
            uint256 proportionalBaseVolume = uint256(
                checkpoints[checkpointTime].longBaseVolume
            ).mulDown(_bondAmount.divDown(checkpointAmount));
            _poolInfo.longBaseVolume -= proportionalBaseVolume;
            checkpoints[checkpointTime].longBaseVolume -= proportionalBaseVolume
                .toUint128();
        }

        // Reduce the amount of outstanding longs.
        _poolInfo.longsOutstanding -= _bondAmount;

        // Apply the updates from the curve trade to the reserves.
        _poolInfo.shareReserves -= _shareReservesDelta;
        _poolInfo.bondReserves += _bondReservesDelta;

        // Remove the flat part of the trade from the pool's liquidity.
        _updateLiquidity(
            _poolInfo,
            -int256(_shareProceeds - _shareReservesDelta)
        );

        // If there are withdrawal shares outstanding, we pay out the maximum
        // amount of withdrawal shares. The proceeds owed to LPs when a long is
        // closed is equivalent to short proceeds as LPs take the other side of
        // every trade.
        uint256 withdrawalSharesOutstanding = totalSupply[
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.WithdrawalShare, 0)
        ] - _poolInfo.withdrawalSharesReadyToWithdraw;
        if (withdrawalSharesOutstanding > 0) {
            // TODO: Test this logic to ensure that opening and closing a long
            // doesn't unfairly treat the withdrawal pool. There are concerns
            // that this allows interest to be dripped out of the long
            // positions.
            uint256 openSharePrice = checkpoints[
                _maturityTime - positionDuration
            ].longSharePrice;
            uint256 withdrawalProceeds = HyperdriveMath.calculateShortProceeds(
                _bondAmount,
                _shareProceeds,
                openSharePrice,
                // TODO: This allows the withdrawal pool to take all of the
                // interest as long as the checkpoint isn't minted. This is
                // probably fine, but it's worth more thought.
                _poolInfo.sharePrice,
                _poolInfo.sharePrice
            );
            _applyWithdrawalProceeds(
                _poolInfo,
                withdrawalProceeds,
                withdrawalSharesOutstanding
            );
        }
    }

    /// @dev Calculate the pool reserve and trader deltas that result from
    ///      opening a long. This calculation includes trading fees.
    /// @param _poolInfo An in-memory representation of the pool's state.
    /// @param _shareAmount The amount of shares being paid to open the long.
    /// @param _timeRemaining The time remaining in the position.
    /// @return shareReservesDelta The change in the share reserves.
    /// @return bondReservesDelta The change in the bond reserves.
    /// @return bondProceeds The proceeds in bonds.
    /// @return totalGovernanceFee The governance fee in shares.
    function _calculateOpenLong(
        IHyperdrive.PoolInfo memory _poolInfo,
        uint256 _shareAmount,
        uint256 _timeRemaining
    )
        internal
        view
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
                _poolInfo.shareReserves,
                _poolInfo.bondReserves,
                _shareAmount, // amountIn
                _timeRemaining,
                timeStretch,
                _poolInfo.sharePrice,
                initialSharePrice
            );

        // Calculate the fees charged on the curve and flat parts of the trade.
        // Since we calculate the amount of bonds received given shares in, we
        // subtract the fee from the bond deltas so that the trader receives
        // less bonds.
        uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
            _poolInfo.shareReserves,
            _poolInfo.bondReserves,
            initialSharePrice,
            _timeRemaining,
            timeStretch
        );
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
                _poolInfo.sharePrice
            );
        bondReservesDelta -= totalCurveFee - governanceCurveFee;
        bondProceeds -= totalCurveFee + totalFlatFee;

        // Calculate the fees owed to governance in shares.
        shareReservesDelta -= governanceCurveFee.divDown(_poolInfo.sharePrice);
        totalGovernanceFee = (governanceCurveFee + governanceFlatFee).divDown(
            _poolInfo.sharePrice
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
    /// @param _poolInfo An in-memory representation of the pool's state.
    /// @param _bondAmount The amount of bonds being purchased to close the short.
    /// @param _maturityTime The maturity time of the short position.
    /// @return shareReservesDelta The change in the share reserves.
    /// @return bondReservesDelta The change in the bond reserves.
    /// @return shareProceeds The proceeds in shares of selling the bonds.
    /// @return totalGovernanceFee The governance fee in shares.
    function _calculateCloseLong(
        IHyperdrive.PoolInfo memory _poolInfo,
        uint256 _bondAmount,
        uint256 _maturityTime
    )
        internal
        view
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
            ? _poolInfo.sharePrice
            : checkpoints[_maturityTime].sharePrice;
        (shareReservesDelta, bondReservesDelta, shareProceeds) = HyperdriveMath
            .calculateCloseLong(
                _poolInfo.shareReserves,
                _poolInfo.bondReserves,
                _bondAmount,
                timeRemaining,
                timeStretch,
                closeSharePrice,
                _poolInfo.sharePrice,
                initialSharePrice
            );

        // Calculate the fees charged on the curve and flat parts of the trade.
        // Since we calculate the amount of shares received given bonds in, we
        // subtract the fee from the share deltas so that the trader receives
        // less shares.
        //
        // TODO: There should be a way to refactor this so that the spot price
        // isn't calculated when the curve fee is 0. The bond reserves are only
        // 0 in the scenario that the LPs have fully withdrawn and the last
        // trader redeems.
        uint256 spotPrice = _poolInfo.bondReserves > 0
            ? HyperdriveMath.calculateSpotPrice(
                _poolInfo.shareReserves,
                _poolInfo.bondReserves,
                initialSharePrice,
                timeRemaining,
                timeStretch
            )
            : FixedPointMath.ONE_18;
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
            _poolInfo.sharePrice
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
