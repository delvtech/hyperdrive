// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";

library HyperdriveUtils {
    using FixedPointMath for uint256;

    struct PoolConfig {
        uint256 initialSharePrice;
        uint256 positionDuration;
        uint256 checkpointDuration;
        uint256 timeStretch;
        uint256 flatFee;
        uint256 curveFee;
        uint256 govFee;
    }

    struct PoolInfo {
        uint256 shareReserves;
        uint256 bondReserves;
        uint256 lpTotalSupply;
        uint256 sharePrice;
        uint256 longsOutstanding;
        uint256 longAverageMaturityTime;
        uint256 longBaseVolume;
        uint256 shortsOutstanding;
        uint256 shortAverageMaturityTime;
        uint256 shortBaseVolume;
    }

    function getPoolConfig(
        IHyperdrive _hyperdrive
    ) internal view returns (PoolConfig memory) {
        (
            uint256 initialSharePrice,
            uint256 positionDuration,
            uint256 checkpointDuration,
            uint256 timeStretch,
            uint256 flatFee,
            uint256 curveFee,
            uint256 govFee
        ) = _hyperdrive.getPoolConfiguration();

        return
            PoolConfig({
                initialSharePrice: initialSharePrice,
                positionDuration: positionDuration,
                checkpointDuration: checkpointDuration,
                timeStretch: timeStretch,
                flatFee: flatFee,
                curveFee: curveFee,
                govFee: govFee
            });
    }

    function getPoolInfo(
        IHyperdrive _hyperdrive
    ) internal view returns (PoolInfo memory) {
        (
            uint256 shareReserves,
            uint256 bondReserves,
            uint256 lpTotalSupply,
            uint256 sharePrice,
            uint256 longsOutstanding,
            uint256 longAverageMaturityTime,
            uint256 longBaseVolume,
            uint256 shortsOutstanding,
            uint256 shortAverageMaturityTime,
            uint256 shortBaseVolume
        ) = _hyperdrive.getPoolInfo();
        return
            PoolInfo({
                shareReserves: shareReserves,
                bondReserves: bondReserves,
                lpTotalSupply: lpTotalSupply,
                sharePrice: sharePrice,
                longsOutstanding: longsOutstanding,
                longAverageMaturityTime: longAverageMaturityTime,
                longBaseVolume: longBaseVolume,
                shortsOutstanding: shortsOutstanding,
                shortAverageMaturityTime: shortAverageMaturityTime,
                shortBaseVolume: shortBaseVolume
            });
    }

    function latestCheckpoint(
        IHyperdrive hyperdrive
    ) internal view returns (uint256) {
        return
            block.timestamp -
            (block.timestamp % getPoolConfig(hyperdrive).checkpointDuration);
    }

    function calculateTimeRemaining(
        IHyperdrive _hyperdrive,
        uint256 _maturityTime
    ) internal view returns (uint256 timeRemaining) {
        timeRemaining = _maturityTime > block.timestamp
            ? _maturityTime - block.timestamp
            : 0;
        timeRemaining = (timeRemaining).divDown(
            getPoolConfig(_hyperdrive).positionDuration
        );
        return timeRemaining;
    }

    function maturityTimeFromLatestCheckpoint(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256) {
        return
            latestCheckpoint(_hyperdrive) +
            getPoolConfig(_hyperdrive).positionDuration;
    }

    function calculateAPRFromReserves(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256) {
        (
            uint256 initialSharePrice,
            uint256 positionDuration,
            ,
            uint256 timeStretch,
            ,
            ,

        ) = _hyperdrive.getPoolConfiguration();
        (
            uint256 shareReserves,
            uint256 bondReserves,
            ,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = _hyperdrive.getPoolInfo();
        return
            HyperdriveMath.calculateAPRFromReserves(
                shareReserves,
                bondReserves,
                initialSharePrice,
                positionDuration,
                timeStretch
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

    function calculateMaxOpenLong(
        IHyperdrive _hyperdrive
    ) internal view returns (uint256 baseAmount) {
        PoolInfo memory poolInfo = getPoolInfo(_hyperdrive);

        uint256 tStretch = getPoolConfig(_hyperdrive).timeStretch;
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
                    getPoolConfig(_hyperdrive).initialSharePrice
                )
                .divDown(poolInfo.sharePrice);
    }

    /// @dev Derives principal + compounded rate of interest over a period
    ///      principal * e ^ (rate * time)
    /// @param _principal The initial amount interest will be accrued on
    /// @param _apr Annual percentage rate
    /// @param _time Number of seconds compounding will occur for
    function calculateCompoundInterest(
        uint256 _principal,
        int256 _apr,
        uint256 _time
    ) public pure returns (uint256 accrued, int256 interest) {
        // Adjust time to a fraction of a year
        uint256 normalizedTime = _time.divDown(365 days);
        uint256 rt = uint256(_apr < 0 ? -_apr : _apr).mulDown(normalizedTime);

        if (_apr > 0) {
            accrued = _principal.mulDown(
                uint256(FixedPointMath.exp(int256(rt)))
            );
            interest = int256(accrued - _principal);
            return (accrued, interest);
        } else if (_apr < 0) {
            // NOTE: Might not be the correct calculation for negatively
            // continuously compounded interest
            accrued = _principal.divDown(
                uint256(FixedPointMath.exp(int256(rt)))
            );
            interest = int256(accrued) - int256(_principal);
            return (accrued, interest);
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
        PoolConfig memory poolConfig = getPoolConfig(_hyperdrive);
        PoolInfo memory poolInfo = getPoolInfo(_hyperdrive);
        uint256 openSharePrice;
        uint256 timeRemaining;
        {
            uint256 checkpoint = latestCheckpoint(_hyperdrive);
            uint256 maturityTime = checkpoint +
                getPoolConfig(_hyperdrive).positionDuration;
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
}
