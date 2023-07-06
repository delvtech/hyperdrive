// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract ExtremeInputs is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    function test_max_open_long() external {
        // Initialize the pools with a large amount of capital.
        initialize(alice, 0.05e18, 500_000_000e18);

        // Calculate amount of base
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Max base amount
        uint256 baseAmount = hyperdrive.calculateMaxLong();

        // Open long with max base amount
        (, uint256 bondAmount) = openLong(bob, baseAmount);
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();

        // Ensure that the ending APR is approximately 0%.
        uint256 apr = hyperdrive.calculateAPRFromReserves();
        assertApproxEqAbs(
            apr,
            0,
            0.001e18, // 0% <= APR < 0.001%
            "APR should be approximately 0%"
        );

        // Ensure that the bond reserves were updated to have the correct APR.
        // Due to the way that the flat part of the trade is applied, the bond
        // reserve updates may not exactly correspond to the amount of bonds
        // transferred; however, the pool's APR should be identical to the APR
        // that the bond amount transfer implies.
        assertApproxEqAbs(
            hyperdrive.calculateAPRFromReserves(),
            HyperdriveMath.calculateAPRFromReserves(
                poolInfoAfter.shareReserves,
                poolInfoBefore.bondReserves - bondAmount,
                INITIAL_SHARE_PRICE,
                POSITION_DURATION,
                hyperdrive.getPoolConfig().timeStretch
            ),
            5
        );
    }

    function test_max_open_short() external {
        // Initialize the pools with a large amount of capital.
        initialize(alice, 0.05e18, 500_000_000e18);

        // Calculate amount of base
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Max amount of bonds to short
        uint256 bondAmount = hyperdrive.calculateMaxShort();

        // Open short with max base amount
        uint256 aprBefore = hyperdrive.calculateAPRFromReserves();
        openShort(bob, bondAmount);
        uint256 aprAfter = hyperdrive.calculateAPRFromReserves();

        // Ensure the share reserves are approximately equal to the minimum
        // share reserves and that the apr increased.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();
        assertApproxEqAbs(
            poolInfoAfter.shareReserves,
            hyperdrive.getPoolConfig().minimumShareReserves,
            1e10,
            "shareReserves should be the minimum share reserves"
        );
        assertGt(aprAfter, aprBefore);

        // Ensure that the bond reserves were updated to have the correct APR.
        // Due to the way that the flat part of the trade is applied, the bond
        // reserve updates may not exactly correspond to the amount of bonds
        // transferred; however, the pool's APR should be identical to the APR
        // that the bond amount transfer implies.
        assertApproxEqAbs(
            hyperdrive.calculateAPRFromReserves(),
            HyperdriveMath.calculateAPRFromReserves(
                poolInfoAfter.shareReserves,
                poolInfoBefore.bondReserves + bondAmount,
                INITIAL_SHARE_PRICE,
                POSITION_DURATION,
                hyperdrive.getPoolConfig().timeStretch
            ),
            5
        );
    }

    // This test verifies that the share reserves can't be brought below the
    // minimum share reserves.
    function test_short_below_minimum_share_reserves(
        uint256 targetReserves
    ) external {
        uint256 fixedRate = 0.02e18;

        // Deploy the pool with a small minimum share reserves.
        IHyperdrive.PoolConfig memory config = testConfig(fixedRate);
        config.minimumShareReserves = 1e6;
        deploy(deployer, config);

        // Alice initializes the pool.
        uint256 contribution = 500_000_000e6;
        initialize(alice, fixedRate, contribution);

        // Bob attempts to short exactly the maximum amount of bonds needed for
        // the share reserves to be equal to zero. This should fail because the
        // share reserves fall below the minimum share reserves.
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        IHyperdrive.PoolConfig memory poolConfig = hyperdrive.getPoolConfig();
        targetReserves = targetReserves.normalizeToRange(
            0,
            poolConfig.minimumShareReserves - 1
        );
        uint256 shortAmount = HyperdriveMath.calculateMaxShort(
            HyperdriveMath.MaxTradeParams({
                shareReserves: poolInfo.shareReserves,
                bondReserves: poolInfo.bondReserves,
                longsOutstanding: poolInfo.longsOutstanding,
                timeStretch: poolConfig.timeStretch,
                sharePrice: poolInfo.sharePrice,
                initialSharePrice: poolConfig.initialSharePrice,
                minimumShareReserves: targetReserves
            })
        );
        baseToken.mint(shortAmount);
        baseToken.approve(address(hyperdrive), shortAmount);
        vm.expectRevert(IHyperdrive.BaseBufferExceedsShareReserves.selector);
        hyperdrive.openShort(shortAmount, type(uint256).max, bob, true);
    }
}
