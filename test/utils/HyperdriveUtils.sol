// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { Errors } from "contracts/src/libraries/Errors.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockHyperdrive } from "../mocks/MockHyperdrive.sol";

library HyperdriveUtils {
    using FixedPointMath for uint256;

    function latestCheckpoint(
        IHyperdrive hyperdrive
    ) internal view returns (uint256) {
        return
            block.timestamp -
            (block.timestamp % hyperdrive.getPoolConfig().checkpointDuration);
    }

    function calculateTimeRemaining(
        IHyperdrive _hyperdrive,
        uint256 _maturityTime
    ) internal view returns (uint256 timeRemaining) {
        timeRemaining = _maturityTime > block.timestamp
            ? _maturityTime - block.timestamp
            : 0;
        timeRemaining = (timeRemaining).divDown(
            _hyperdrive.getPoolConfig().positionDuration
        );
        return timeRemaining;
    }

    function maturityTimeFromLatestCheckpoint(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256) {
        return
            latestCheckpoint(_hyperdrive) +
            _hyperdrive.getPoolConfig().positionDuration;
    }

    function calculateAPRFromReserves(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256) {
        IHyperdrive.PoolConfig memory poolConfig = _hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory poolInfo = _hyperdrive.getPoolInfo();
        return
            HyperdriveMath.calculateAPRFromReserves(
                poolInfo.shareReserves,
                poolInfo.bondReserves,
                poolConfig.initialSharePrice,
                poolConfig.positionDuration,
                poolConfig.timeStretch
            );
    }

    function calculateAPRFromRealizedPrice(
        uint256 baseAmount,
        uint256 bondAmount,
        uint256 timeRemaining
    ) internal pure returns (uint256) {
        // price = dx / dy
        //       =>
        // rate = (1 - p) / (p * t) = (1 - dx / dy) * (dx / dy * t)
        //       =>
        // apr = (dy - dx) / (dx * t)
        return
            (bondAmount.sub(baseAmount)).divDown(
                baseAmount.mulDown(timeRemaining)
            );
    }

    function calculateMaxLong(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256 baseAmount) {
        IHyperdrive.PoolInfo memory poolInfo = _hyperdrive.getPoolInfo();
        IHyperdrive.PoolConfig memory poolConfig = _hyperdrive.getPoolConfig();

        uint256 tStretch = poolConfig.timeStretch;
        // As any long in the middle of a checkpoint duration is backdated,
        // we must use that backdate as the reference for the maturity time
        uint256 maturityTime = maturityTimeFromLatestCheckpoint(_hyperdrive);
        uint256 timeRemaining = calculateTimeRemaining(
            _hyperdrive,
            maturityTime
        );
        // 1 - t * s
        // t = normalized seconds until maturity
        // s = time stretch of the pool
        uint256 normalizedTimeRemaining = FixedPointMath.ONE_18.sub(
            timeRemaining.mulDown(tStretch)
        );

        // TODO: This isn't as accurate as it could be. We should be using flat
        // plus curve to handle backdating. Address this when adding tests for
        // the backdating logic.
        //
        // The max amount of base is derived by approximating the bondReserve
        // as the theoretical amount of bondsOut. As openLong specifies an
        // amount of base, the conversion of shares to base must also be derived
        return
            YieldSpaceMath
                .calculateSharesInGivenBondsOut(
                    poolInfo.shareReserves,
                    poolInfo.bondReserves,
                    (poolInfo.bondReserves -
                        _hyperdrive.totalSupply(AssetId._LP_ASSET_ID)),
                    normalizedTimeRemaining,
                    poolInfo.sharePrice,
                    poolConfig.initialSharePrice
                )
                .divDown(poolInfo.sharePrice);
    }

    function calculateMaxShort(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256) {
        IHyperdrive.PoolInfo memory poolInfo = _hyperdrive.getPoolInfo();

        // As any long in the middle of a checkpoint duration is backdated,
        // we must use that backdate as the reference for the maturity time
        uint256 maturityTime = maturityTimeFromLatestCheckpoint(_hyperdrive);
        uint256 timeRemaining = calculateTimeRemaining(
            _hyperdrive,
            maturityTime
        );
        // 1 - t * s
        // t = normalized seconds until maturity
        // s = time stretch of the pool
        uint256 normalizedTimeRemaining = FixedPointMath.ONE_18.sub(
            timeRemaining.mulDown(_hyperdrive.getPoolConfig().timeStretch)
        );

        // The calculate bonds in given shares out function slightly
        // overestimates the amount of bondsOut, so we decrease the input
        // slightly to avoid subtraction underflows.
        uint256 sharesOut = poolInfo.shareReserves -
            poolInfo.longsOutstanding.divUp(poolInfo.sharePrice);
        sharesOut = sharesOut > 1e10 ? sharesOut - 1e10 : 0;

        // TODO: This isn't as accurate as it could be. We should be using flat
        // plus curve to handle backdating. Address this when adding tests for
        // the backdating logic.
        //
        // The max amount of base is derived by approximating the share reserve
        // minus the base buffer as the theoretical amount of sharesOut.
        return
            YieldSpaceMath
                .calculateBondsInGivenSharesOut(
                    poolInfo.shareReserves,
                    poolInfo.bondReserves,
                    sharesOut,
                    normalizedTimeRemaining,
                    poolInfo.sharePrice,
                    _hyperdrive.getPoolConfig().initialSharePrice
                )
                .divDown(poolInfo.sharePrice);
    }

    /// @dev Calculates the non-compounded interest over a period.
    /// @param _principal The principal amount that will accrue interest.
    /// @param _apr Annual percentage rate
    /// @param _time Amount of time in seconds over which interest accrues.
    /// @return totalAmount The total amount of capital after interest accrues.
    /// @return interest The interest that accrued.
    function calculateInterest(
        uint256 _principal,
        int256 _apr,
        uint256 _time
    ) internal pure returns (uint256 totalAmount, int256 interest) {
        // Adjust time to a fraction of a year
        uint256 normalizedTime = _time.divDown(365 days);
        interest = _apr >= 0
            ? int256(_principal.mulDown(uint256(_apr).mulDown(normalizedTime)))
            : -int256(
                _principal.mulDown(uint256(-_apr).mulDown(normalizedTime))
            );
        totalAmount = uint256(int256(_principal) + interest);
        return (totalAmount, interest);
    }

    /// @dev Calculates principal + compounded rate of interest over a period
    ///      principal * e ^ (rate * time)
    /// @param _principal The initial amount interest will be accrued on
    /// @param _apr Annual percentage rate
    /// @param _time Number of seconds compounding will occur for
    /// @return totalAmount The total amount of capital after interest accrues.
    /// @return interest The interest that accrued.
    function calculateCompoundInterest(
        uint256 _principal,
        int256 _apr,
        uint256 _time
    ) internal pure returns (uint256 totalAmount, int256 interest) {
        // Adjust time to a fraction of a year
        uint256 normalizedTime = _time.divDown(365 days);
        uint256 rt = uint256(_apr < 0 ? -_apr : _apr).mulDown(normalizedTime);

        if (_apr > 0) {
            totalAmount = _principal.mulDown(
                uint256(FixedPointMath.exp(int256(rt)))
            );
            interest = int256(totalAmount - _principal);
            return (totalAmount, interest);
        } else if (_apr < 0) {
            // NOTE: Might not be the correct calculation for negatively
            // continuously compounded interest
            totalAmount = _principal.divDown(
                uint256(FixedPointMath.exp(int256(rt)))
            );
            interest = int256(totalAmount) - int256(_principal);
            return (totalAmount, interest);
        }
        return (_principal, 0);
    }

    function calculateTimeStretch(uint256 apr) internal pure returns (uint256) {
        uint256 timeStretch = uint256(3.09396e18).divDown(
            uint256(0.02789e18).mulDown(apr * 100)
        );
        return FixedPointMath.ONE_18.divDown(timeStretch);
    }

    function calculateOpenShortDeposit(
        IHyperdrive _hyperdrive,
        uint256 _bondAmount
    ) internal view returns (uint256) {
        // Retrieve hyperdrive pool state
        IHyperdrive.PoolConfig memory poolConfig = _hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory poolInfo = _hyperdrive.getPoolInfo();
        uint256 openSharePrice;
        uint256 timeRemaining;
        {
            uint256 checkpoint = latestCheckpoint(_hyperdrive);
            uint256 maturityTime = checkpoint + poolConfig.positionDuration;
            timeRemaining = calculateTimeRemaining(_hyperdrive, maturityTime);
            openSharePrice = _hyperdrive.checkpoints(checkpoint).sharePrice;
        }

        // Calculate the openShort trade
        (, , uint256 shareProceeds) = HyperdriveMath.calculateOpenShort(
            poolInfo.shareReserves,
            poolInfo.bondReserves,
            _bondAmount,
            timeRemaining,
            poolConfig.timeStretch,
            poolInfo.sharePrice,
            poolConfig.initialSharePrice
        );

        // Price without slippage of bonds in terms of shares
        uint256 spotPrice = HyperdriveMath.calculateSpotPrice(
            poolInfo.shareReserves,
            poolInfo.bondReserves,
            poolConfig.initialSharePrice,
            timeRemaining,
            poolConfig.timeStretch
        );

        // Calculate and attribute fees
        uint256 curveFee = FixedPointMath
            .ONE_18
            .sub(spotPrice)
            .mulDown(poolConfig.curveFee)
            .mulDown(_bondAmount)
            .mulDivDown(timeRemaining, poolInfo.sharePrice);
        uint256 flatFee = (
            _bondAmount.mulDivDown(
                FixedPointMath.ONE_18.sub(timeRemaining),
                poolInfo.sharePrice
            )
        ).mulDown(poolConfig.flatFee);
        shareProceeds -= curveFee + flatFee;

        // Return the proceeds of the short
        return
            HyperdriveMath
                .calculateShortProceeds(
                    _bondAmount,
                    shareProceeds,
                    openSharePrice,
                    poolInfo.sharePrice,
                    poolInfo.sharePrice
                )
                .mulDown(poolInfo.sharePrice);
    }

    struct OpenLongTradeDetails {
        uint256 timestamp;
        uint256 latestCheckpoint;
        uint256 maturityTime;
        uint256 sharePrice;
        uint256 baseAmount;
        uint256 shares;
        uint256 normalizedTimeRemaining;
        uint256 initialShareReservesDelta;
        uint256 initialBondReservesDelta;
        uint256 initialBondProceeds;
        uint256 bondReservesDelta;
        uint256 shareReservesDelta;
        uint256 bondProceeds;
        uint256 spotPrice;
        uint256 totalCurveFee;
        uint256 totalFlatFee;
        uint256 governanceCurveFee;
        uint256 governanceFlatFee;
        IHyperdrive.PoolInfo poolInfoBefore;
        IHyperdrive.PoolInfo poolInfoAfter;
    }

    function openLongTradeDetails(
        IHyperdrive _hyperdrive,
        uint256 _baseAmount,
        uint256 _maturityTime
    ) external view returns (OpenLongTradeDetails memory _details) {
        IHyperdrive.PoolConfig memory poolConfig = _hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory poolInfo = _hyperdrive.getPoolInfo();
        _details.poolInfoBefore = poolInfo;

        _details.timestamp = block.timestamp;
        _details.latestCheckpoint = latestCheckpoint(_hyperdrive);
        _details.maturityTime = _maturityTime;
        _details.baseAmount = _baseAmount;

        {
            // TODO Would be more elegant to have MockHyperdrive use ERC4626 for
            // a more elegant solution to this
            uint256 assets = IERC20(_hyperdrive.baseToken()).balanceOf(
                address(_hyperdrive)
            );
            uint256 totalShares = MockHyperdrive(address(_hyperdrive))
                .totalShares();

            if (totalShares == 0) {
                _details.shares = _baseAmount;
                _details.sharePrice = FixedPointMath.ONE_18;
            } else {
                _details.shares = totalShares.mulDivDown(_baseAmount, assets);
                _details.sharePrice = _baseAmount.divDown(_details.shares);
            }
        }

        _details.normalizedTimeRemaining = calculateTimeRemaining(
            _hyperdrive,
            _maturityTime
        );

        (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 bondProceeds
        ) = HyperdriveMath.calculateOpenLong(
                poolInfo.shareReserves,
                poolInfo.bondReserves,
                _details.shares,
                _details.normalizedTimeRemaining,
                poolConfig.timeStretch,
                _details.sharePrice,
                poolConfig.initialSharePrice
            );

        _details.initialShareReservesDelta = shareReservesDelta;
        _details.initialBondProceeds = bondProceeds;
        _details.bondReservesDelta = bondReservesDelta;

        _details.spotPrice = HyperdriveMath.calculateSpotPrice(
            poolInfo.shareReserves,
            poolInfo.bondReserves,
            poolConfig.initialSharePrice,
            _details.normalizedTimeRemaining,
            poolConfig.timeStretch
        );

        {
            (
                uint256 totalCurveFee,
                uint256 totalFlatFee,
                uint256 governanceCurveFee,
                uint256 governanceFlatFee
            ) = MockHyperdrive(address(_hyperdrive))
                    .calculateFeesOutGivenSharesIn(
                        _details.shares,
                        _details.initialBondProceeds,
                        _details.normalizedTimeRemaining,
                        _details.spotPrice,
                        poolInfo.sharePrice
                    );
            _details.totalCurveFee = totalCurveFee;
            _details.totalFlatFee = totalFlatFee;
            _details.governanceCurveFee = governanceCurveFee;
            _details.governanceFlatFee = governanceFlatFee;

            _details.bondReservesDelta =
                bondReservesDelta -
                (totalCurveFee - governanceCurveFee);
            _details.bondProceeds =
                bondProceeds -
                (totalCurveFee + totalFlatFee);
            _details.shareReservesDelta =
                shareReservesDelta -
                (governanceCurveFee.divDown(_details.sharePrice));
        }
    }

    struct CloseLongTradeDetails {
        uint256 timestamp;
        uint256 latestCheckpoint;
        uint256 maturityTime;
        uint256 bondAmount;
        uint256 sharePrice;
        uint256 normalizedTimeRemaining;
        uint256 closeSharePrice;
        uint256 initialShareReservesDelta;
        uint256 initialShareProceeds;
        uint256 bondReservesDelta;
        uint256 shareReservesDelta;
        uint256 shareProceeds;
        uint256 spotPrice;
        uint256 totalCurveFee;
        uint256 totalFlatFee;
        uint256 totalGovernanceFee;
        uint256 baseProceeds;
        IHyperdrive.PoolInfo poolInfoBefore;
        IHyperdrive.PoolInfo poolInfoAfter;
    }

    function closeLongTradeDetails(
        IHyperdrive _hyperdrive,
        uint256 _bondAmount,
        uint256 _maturityTime
    ) external view returns (CloseLongTradeDetails memory _details) {
        _details.timestamp = block.timestamp;
        _details.latestCheckpoint = latestCheckpoint(_hyperdrive);
        _details.maturityTime = _maturityTime;
        _details.bondAmount = _bondAmount;

        IHyperdrive.PoolConfig memory poolConfig = _hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory poolInfo = _hyperdrive.getPoolInfo();
        _details.poolInfoBefore = poolInfo;

        _details.sharePrice = poolInfo.sharePrice;
        _details.normalizedTimeRemaining = calculateTimeRemaining(
            _hyperdrive,
            _maturityTime
        );

        // NOTE: Slight discrepancy to real implementation due to future
        // checkpoint application
        uint256 maturitySharePrice = _hyperdrive.checkpoints(_maturityTime).sharePrice;
        _details.closeSharePrice = block.timestamp < _maturityTime
            ? _details.sharePrice
            : maturitySharePrice == 0 ? _details.sharePrice : maturitySharePrice;

        (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 shareProceeds
        ) = HyperdriveMath.calculateCloseLong(
                poolInfo.shareReserves,
                poolInfo.bondReserves,
                _bondAmount,
                _details.normalizedTimeRemaining,
                poolConfig.timeStretch,
                _details.closeSharePrice,
                poolInfo.sharePrice,
                poolConfig.initialSharePrice
            );

        _details.initialShareReservesDelta = shareReservesDelta;
        _details.bondReservesDelta = bondReservesDelta;
        _details.initialShareProceeds = shareProceeds;

        _details.spotPrice = poolInfo.bondReserves > 0
            ? HyperdriveMath.calculateSpotPrice(
                poolInfo.shareReserves,
                poolInfo.bondReserves,
                poolConfig.initialSharePrice,
                _details.normalizedTimeRemaining,
                poolConfig.timeStretch
            )
            : FixedPointMath.ONE_18;

        {
            (
                uint256 totalCurveFee,
                uint256 totalFlatFee,
                uint256 totalGovernanceFee
            ) = MockHyperdrive(address(_hyperdrive))
                    .calculateFeesOutGivenBondsIn(
                        _bondAmount,
                        _details.normalizedTimeRemaining,
                        _details.spotPrice,
                        poolInfo.sharePrice
                    );
            _details.totalCurveFee = totalCurveFee;
            _details.totalFlatFee = totalFlatFee;
            _details.totalGovernanceFee = totalGovernanceFee;

            _details.shareReservesDelta =
                shareReservesDelta -
                totalCurveFee;
            _details.shareProceeds =
                shareProceeds -
                (totalCurveFee + totalFlatFee);
        }

        // TODO Would be more elegant to have MockHyperdrive use ERC4626 for
        // a more elegant solutions to this
        uint256 assets = IERC20(_hyperdrive.baseToken()).balanceOf(
            address(_hyperdrive)
        );
        uint256 totalShares = MockHyperdrive(address(_hyperdrive))
            .totalShares();
        uint256 shares = _details.shareProceeds > totalShares
            ? totalShares
            : _details.shareProceeds;
        _details.baseProceeds = totalShares != 0
            ? shares.mulDown(assets.divDown(totalShares))
            : 0;
    }

    struct OpenShortTradeDetails {
        uint256 timestamp;
        uint256 latestCheckpoint;
        uint256 maturityTime;
        uint256 bondAmount;
        uint256 sharePrice;
        uint256 openSharePrice;
        uint256 normalizedTimeRemaining;
        uint256 initialShareReservesDelta;
        uint256 initialShareProceeds;
        uint256 bondReservesDelta;
        uint256 shareReservesDelta;
        uint256 shareProceeds;
        uint256 spotPrice;
        uint256 totalCurveFee;
        uint256 totalFlatFee;
        uint256 totalGovernanceFee;
        uint256 sharesDeposit;
        uint256 baseDeposit;
        IHyperdrive.PoolInfo poolInfoBefore;
        IHyperdrive.PoolInfo poolInfoAfter;
    }

    function openShortTradeDetails(
        IHyperdrive _hyperdrive,
        uint256 _bondAmount,
        uint256 _maturityTime
    ) external view returns (OpenShortTradeDetails memory _details) {
        _details.timestamp = block.timestamp;
        _details.latestCheckpoint = latestCheckpoint(_hyperdrive);
        _details.maturityTime = _maturityTime;

        _details.bondAmount = _bondAmount;

        IHyperdrive.PoolConfig memory poolConfig = _hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory poolInfo = _hyperdrive.getPoolInfo();
        _details.poolInfoBefore = poolInfo;

        _details.sharePrice = poolInfo.sharePrice;
        {
            uint256 checkpointSharePrice = _hyperdrive
                .checkpoints(_details.latestCheckpoint)
                .sharePrice;
            _details.openSharePrice = checkpointSharePrice != 0
                ? checkpointSharePrice
                : poolInfo.sharePrice;
        }
        _details.normalizedTimeRemaining = calculateTimeRemaining(
            _hyperdrive,
            _maturityTime
        );

        (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 shareProceeds
        ) = HyperdriveMath.calculateOpenShort(
                poolInfo.shareReserves,
                poolInfo.bondReserves,
                _bondAmount,
                _details.normalizedTimeRemaining,
                poolConfig.timeStretch,
                poolInfo.sharePrice,
                poolConfig.initialSharePrice
            );

        _details.initialShareReservesDelta = shareReservesDelta;
        _details.initialShareProceeds = shareProceeds;
        _details.bondReservesDelta = bondReservesDelta;

        if (
            _details.initialShareProceeds.mulDown(poolInfo.sharePrice) >
            _bondAmount
        ) revert Errors.NegativeInterest();

        _details.spotPrice = HyperdriveMath.calculateSpotPrice(
            poolInfo.shareReserves,
            poolInfo.bondReserves,
            poolConfig.initialSharePrice,
            _details.normalizedTimeRemaining,
            poolConfig.timeStretch
        );

        {
            (
                uint256 totalCurveFee,
                uint256 totalFlatFee,
                uint256 totalGovernanceFee
            ) = MockHyperdrive(address(_hyperdrive))
                    .calculateFeesOutGivenBondsIn(
                        _bondAmount,
                        _details.normalizedTimeRemaining,
                        _details.spotPrice,
                        poolInfo.sharePrice
                    );
            _details.totalCurveFee = totalCurveFee;
            _details.totalFlatFee = totalFlatFee;
            _details.totalGovernanceFee = totalGovernanceFee;

            _details.shareReservesDelta =
                _details.initialShareReservesDelta -
                totalCurveFee;
            _details.shareProceeds =
                _details.initialShareProceeds -
                (totalCurveFee + totalFlatFee);
        }

        _details.sharesDeposit = HyperdriveMath.calculateShortProceeds(
            _bondAmount,
            _details.shareProceeds,
            _details.openSharePrice,
            poolInfo.sharePrice,
            poolInfo.sharePrice
        );
        _details.baseDeposit = _details.sharesDeposit.mulDown(
            poolInfo.sharePrice
        );
    }

    struct CloseShortTradeDetails {
        uint256 timestamp;
        uint256 latestCheckpoint;
        uint256 maturityTime;
        uint256 bondAmount;
        uint256 sharePrice;
        uint256 normalizedTimeRemaining;
        uint256 initialShareReservesDelta;
        uint256 initialSharePayment;
        uint256 bondReservesDelta;
        uint256 shareReservesDelta;
        uint256 sharePayment;
        uint256 spotPrice;
        uint256 totalCurveFee;
        uint256 totalFlatFee;
        uint256 governanceCurveFee;
        uint256 governanceFlatFee;
        uint256 openSharePrice;
        uint256 closeSharePrice;
        uint256 shareProceeds;
        uint256 baseProceeds;
        IHyperdrive.PoolInfo poolInfoBefore;
        IHyperdrive.PoolInfo poolInfoAfter;
    }

    function closeShortTradeDetails(
        IHyperdrive _hyperdrive,
        uint256 _bondAmount,
        uint256 _maturityTime
    ) external view returns (CloseShortTradeDetails memory _details) {
        _details.timestamp = block.timestamp;
        _details.latestCheckpoint = latestCheckpoint(_hyperdrive);
        _details.maturityTime = _maturityTime;

        _details.bondAmount = _bondAmount;

        IHyperdrive.PoolConfig memory poolConfig = _hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory poolInfo = _hyperdrive.getPoolInfo();
        _details.poolInfoBefore = poolInfo;

        _details.sharePrice = poolInfo.sharePrice;
        _details.normalizedTimeRemaining = calculateTimeRemaining(
            _hyperdrive,
            _maturityTime
        );

        (
            uint256 shareReservesDelta,
            uint256 bondReservesDelta,
            uint256 sharePayment
        ) = HyperdriveMath.calculateCloseShort(
                poolInfo.shareReserves,
                poolInfo.bondReserves,
                _bondAmount,
                _details.normalizedTimeRemaining,
                poolConfig.timeStretch,
                poolInfo.sharePrice,
                poolConfig.initialSharePrice
            );

        _details.initialShareReservesDelta = shareReservesDelta;
        _details.initialSharePayment = sharePayment;
        _details.bondReservesDelta = bondReservesDelta;

        _details.spotPrice = poolInfo.bondReserves > 0
            ? HyperdriveMath.calculateSpotPrice(
                poolInfo.shareReserves,
                poolInfo.bondReserves,
                poolConfig.initialSharePrice,
                _details.normalizedTimeRemaining,
                poolConfig.timeStretch
            )
            : FixedPointMath.ONE_18;

        {
            (
                uint256 totalCurveFee,
                uint256 totalFlatFee,
                uint256 governanceCurveFee,
                uint256 governanceFlatFee
            ) = MockHyperdrive(address(_hyperdrive))
                    .calculateFeesInGivenBondsOut(
                        _bondAmount,
                        _details.normalizedTimeRemaining,
                        _details.spotPrice,
                        poolInfo.sharePrice
                    );
            _details.totalCurveFee = totalCurveFee;
            _details.totalFlatFee = totalFlatFee;
            _details.governanceCurveFee = governanceCurveFee;
            _details.governanceFlatFee = governanceFlatFee;

            _details.shareReservesDelta =
                shareReservesDelta +
                (totalCurveFee - governanceCurveFee);
            _details.sharePayment = sharePayment + totalCurveFee + totalFlatFee;
        }

        _details.openSharePrice = _hyperdrive
            .checkpoints(_maturityTime - poolConfig.positionDuration)
            .sharePrice;
        // NOTE This condition differs from real implementation as there is
        // a preceding checkpoint application in such cases
        _details.closeSharePrice = _maturityTime < block.timestamp
            ? _hyperdrive.checkpoints(_maturityTime).sharePrice
            : poolInfo.sharePrice;

        _details.shareProceeds = HyperdriveMath.calculateShortProceeds(
            _bondAmount,
            _details.sharePayment,
            _details.openSharePrice,
            _details.closeSharePrice,
            poolInfo.sharePrice
        );

        // TODO Would be more elegant to have MockHyperdrive use ERC4626 for
        // a more elegant solutions to this
        uint256 assets = IERC20(_hyperdrive.baseToken()).balanceOf(
            address(_hyperdrive)
        );
        uint256 totalShares = MockHyperdrive(address(_hyperdrive))
            .totalShares();
        uint256 shares = _details.shareProceeds > totalShares
            ? totalShares
            : _details.shareProceeds;
        _details.baseProceeds = totalShares != 0
            ? shares.mulDown(assets.divDown(totalShares))
            : 0;
    }
}
