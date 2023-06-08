// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";

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
        timeRemaining = _maturityTime > latestCheckpoint(_hyperdrive)
            ? _maturityTime - latestCheckpoint(_hyperdrive)
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
        uint256 timeStretch = uint256(5.24592e18).divDown(
            uint256(0.04665e18).mulDown(apr * 100)
        );
        return FixedPointMath.ONE_18.divDown(timeStretch);
    }

    // FIXME: This should be removed.
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
            openSharePrice = _hyperdrive.getCheckpoint(checkpoint).sharePrice;
        }

        // Calculate the openShort trade
        uint256 shareProceeds = HyperdriveMath.calculateOpenShort(
            poolInfo.shareReserves,
            poolInfo.bondReserves,
            _bondAmount,
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
            .mulDown(poolConfig.fees.curve)
            .mulDown(_bondAmount)
            .mulDivDown(timeRemaining, poolInfo.sharePrice);
        uint256 flatFee = (
            _bondAmount.mulDivDown(
                FixedPointMath.ONE_18.sub(timeRemaining),
                poolInfo.sharePrice
            )
        ).mulDown(poolConfig.fees.flat);
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

    function presentValue(
        IHyperdrive hyperdrive
    ) internal view returns (uint256) {
        IHyperdrive.PoolConfig memory poolConfig = hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        return
            HyperdriveMath
                .calculatePresentValue(
                    HyperdriveMath.PresentValueParams({
                        shareReserves: poolInfo.shareReserves,
                        bondReserves: poolInfo.bondReserves,
                        sharePrice: poolInfo.sharePrice,
                        initialSharePrice: poolConfig.initialSharePrice,
                        timeStretch: poolConfig.timeStretch,
                        longsOutstanding: poolInfo.longsOutstanding,
                        longAverageTimeRemaining: calculateTimeRemaining(
                            hyperdrive,
                            uint256(poolInfo.longAverageMaturityTime).divUp(
                                1e36
                            )
                        ),
                        shortsOutstanding: poolInfo.shortsOutstanding,
                        shortAverageTimeRemaining: calculateTimeRemaining(
                            hyperdrive,
                            uint256(poolInfo.shortAverageMaturityTime).divUp(
                                1e36
                            )
                        ),
                        shortBaseVolume: poolInfo.shortBaseVolume
                    })
                )
                .mulDown(poolInfo.sharePrice);
    }
}
