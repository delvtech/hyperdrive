// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { BaseTest } from "./BaseTest.sol";
import { ForwarderFactory } from "contracts/src/ForwarderFactory.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { HyperdriveBase } from "contracts/src/HyperdriveBase.sol";
import { MockHyperdrive } from "contracts/test/MockHyperdrive.sol";

contract HyperdriveTest is BaseTest {
    using FixedPointMath for uint256;

    ERC20Mintable baseToken;
    MockHyperdrive hyperdrive;

    uint256 internal constant INITIAL_SHARE_PRICE = FixedPointMath.ONE_18;
    uint256 internal constant CHECKPOINT_DURATION = 1 days;
    uint256 internal constant CHECKPOINTS_PER_TERM = 365;
    uint256 internal constant POSITION_DURATION =
        CHECKPOINT_DURATION * CHECKPOINTS_PER_TERM;

    function setUp() public override {
        super.setUp();
        vm.startPrank(alice);

        // Instantiate the base token.
        baseToken = new ERC20Mintable();
        HyperdriveBase.Fees memory fees = HyperdriveBase.Fees(0, 0, 0);
        // Instantiate Hyperdrive.
        uint256 apr = 0.05e18;
        hyperdrive = new MockHyperdrive(
            baseToken,
            INITIAL_SHARE_PRICE,
            CHECKPOINTS_PER_TERM,
            CHECKPOINT_DURATION,
            calculateTimeStretch(apr),
            fees,
            governance
        );

        // Advance time so that Hyperdrive can look back more than a position
        // duration.
        vm.warp(POSITION_DURATION * 3);
    }

    function deploy(
        address deployer,
        uint256 apr,
        uint256 curveFee,
        uint256 flatFee,
        uint256 govFee,
        address governance
    ) internal {
        vm.stopPrank();
        vm.startPrank(deployer);
        HyperdriveBase.Fees memory fees = HyperdriveBase.Fees(
            curveFee,
            flatFee,
            govFee
        );

        hyperdrive = new MockHyperdrive(
            baseToken,
            INITIAL_SHARE_PRICE,
            CHECKPOINTS_PER_TERM,
            CHECKPOINT_DURATION,
            calculateTimeStretch(apr),
            fees,
            governance
        );
    }

    /// Actions ///

    function initialize(
        address lp,
        uint256 apr,
        uint256 contribution
    ) internal returns (uint256 lpShares) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Initialize the pool.
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        hyperdrive.initialize(contribution, apr, lp, true);

        return hyperdrive.balanceOf(AssetId._LP_ASSET_ID, lp);
    }

    function addLiquidity(
        address lp,
        uint256 contribution
    ) internal returns (uint256 lpShares) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Add liquidity to the pool.
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        hyperdrive.addLiquidity(contribution, 0, type(uint256).max, lp, true);

        return hyperdrive.balanceOf(AssetId._LP_ASSET_ID, lp);
    }

    function removeLiquidity(
        address lp,
        uint256 shares
    ) internal returns (uint256 baseProceeds) {
        vm.stopPrank();
        vm.startPrank(lp);

        // Remove liquidity from the pool.
        uint256 baseBalanceBefore = baseToken.balanceOf(lp);
        hyperdrive.removeLiquidity(shares, 0, lp, true);

        return baseToken.balanceOf(lp) - baseBalanceBefore;
    }

    function openLong(
        address trader,
        uint256 baseAmount
    ) internal returns (uint256 maturityTime, uint256 bondAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Open the long.
        maturityTime = latestCheckpoint() + POSITION_DURATION;
        uint256 bondBalanceBefore = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            trader
        );
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        hyperdrive.openLong(baseAmount, 0, trader, true);

        uint256 bondBalanceAfter = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            trader
        );
        return (maturityTime, bondBalanceAfter.sub(bondBalanceBefore));
    }

    function closeLong(
        address trader,
        uint256 maturityTime,
        uint256 bondAmount
    ) internal returns (uint256 baseAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Close the long.
        uint256 baseBalanceBefore = baseToken.balanceOf(trader);
        hyperdrive.closeLong(maturityTime, bondAmount, 0, trader, true);

        uint256 baseBalanceAfter = baseToken.balanceOf(trader);
        return baseBalanceAfter.sub(baseBalanceBefore);
    }

    function openShort(
        address trader,
        uint256 bondAmount
    ) internal returns (uint256 maturityTime, uint256 baseAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Open the short
        maturityTime = latestCheckpoint() + POSITION_DURATION;
        baseToken.mint(bondAmount);
        baseToken.approve(address(hyperdrive), bondAmount);
        uint256 baseBalanceBefore = baseToken.balanceOf(trader);
        hyperdrive.openShort(bondAmount, bondAmount, trader, true);

        baseAmount = baseBalanceBefore - baseToken.balanceOf(trader);
        baseToken.burn(bondAmount - baseAmount);
        return (maturityTime, baseAmount);
    }

    function closeShort(
        address trader,
        uint256 maturityTime,
        uint256 bondAmount
    ) internal returns (uint256 baseAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Close the short
        uint256 baseBalanceBefore = baseToken.balanceOf(trader);
        hyperdrive.closeShort(maturityTime, bondAmount, 0, trader, true);

        return baseToken.balanceOf(trader) - baseBalanceBefore;
    }

    /// Utils ///
    function advanceTime(uint256 time, int256 apr) internal {
        hyperdrive.accrue(time, apr);
        vm.warp(block.timestamp + time);
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

    function getPoolInfo() internal view returns (PoolInfo memory) {
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
        ) = hyperdrive.getPoolInfo();
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

    function calculateAPRFromReserves() internal view returns (uint256) {
        (
            uint256 initialSharePrice,
            uint256 positionDuration,
            ,
            uint256 timeStretch,
            ,
            ,

        ) = hyperdrive.getPoolConfiguration();
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

        ) = hyperdrive.getPoolInfo();
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

    function calculateTimeRemaining(
        uint256 _maturityTime
    ) internal view returns (uint256 timeRemaining) {
        timeRemaining = _maturityTime > block.timestamp
            ? _maturityTime - block.timestamp
            : 0;
        timeRemaining = (timeRemaining).divDown(POSITION_DURATION);
        return timeRemaining;
    }

    function calculateTimeStretch(uint256 apr) internal pure returns (uint256) {
        uint256 timeStretch = uint256(3.09396e18).divDown(
            uint256(0.02789e18).mulDown(apr * 100)
        );
        return FixedPointMath.ONE_18.divDown(timeStretch);
    }

    function latestCheckpoint() internal view returns (uint256) {
        return block.timestamp - (block.timestamp % CHECKPOINT_DURATION);
    }

    function calculateSpotPrice(
        uint256 shareReserves,
        uint256 bondReserves,
        uint256 sharePrice
    ) internal view returns (uint256) {
        uint256 tStretch = hyperdrive.timeStretch();
        uint256 positionDuration = hyperdrive.positionDuration();
        uint256 maturityTime = latestCheckpoint() + positionDuration;
        uint256 timeRemaining = calculateTimeRemaining(maturityTime);
        return HyperdriveMath.calculateSpotPrice(
                shareReserves,
                bondReserves,
                sharePrice,
                timeRemaining,
                tStretch
            );
    }

    function calculateMaxOpenLong() internal view returns (uint256 baseAmount) {
        PoolInfo memory poolInfo = getPoolInfo();

        uint256 tStretch = hyperdrive.timeStretch();
        uint256 positionDuration = hyperdrive.positionDuration();
        // As any long in the middle of a checkpoint duration is backdated,
        // we must use that backdate as the reference for the maturity time
        uint256 maturityTime = latestCheckpoint() + positionDuration;
        uint256 timeRemaining = calculateTimeRemaining(maturityTime);
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
                    poolInfo.bondReserves -
                        hyperdrive.totalSupply(AssetId._LP_ASSET_ID),
                    normalizedTimeRemaining,
                    poolInfo.sharePrice,
                    hyperdrive.initialSharePrice()
                )
                .divDown(poolInfo.sharePrice);
    }
}
