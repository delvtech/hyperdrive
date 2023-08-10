// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

import "forge-std/console2.sol";

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

    function test_max_open_short_open_long() external {
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

        // Calculate amount of base
        poolInfoBefore = hyperdrive.getPoolInfo();

        // Max base amount
        uint256 baseAmountLong = hyperdrive.calculateMaxLong();

        // Open long with max base amount
        (, uint256 bondAmountLong) = openLong(bob, baseAmountLong);
        poolInfoAfter = hyperdrive.getPoolInfo();

        // Ensure that the bond reserves were updated to have the correct APR.
        // Due to the way that the flat part of the trade is applied, the bond
        // reserve updates may not exactly correspond to the amount of bonds
        // transferred; however, the pool's APR should be identical to the APR
        // that the bond amount transfer implies.
        assertApproxEqAbs(
            hyperdrive.calculateAPRFromReserves(),
            HyperdriveMath.calculateAPRFromReserves(
                poolInfoAfter.shareReserves,
                poolInfoBefore.bondReserves - bondAmountLong,
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

    // This test stresses the edge cases of the `_updateLiquidity` function
    // with sane values that are expected to be used for the most important
    // Hyperdrive integrations.
    function test__updateLiquidity__extremeValues() external {
        uint256 fixedRate = 0.02e18;

        // Test some concrete values with the max long scenario.
        _updateLiquidity__scenario__maxLong(
            10e6,
            fixedRate,
            100_000_000_000e6,
            5_000_000_000e6,
            5_000_000_000e6,
            1e12
        );
        _updateLiquidity__scenario__maxLong(
            1e15,
            fixedRate,
            200_000_000e18,
            100_000_000e18,
            100_000_000e18,
            1
        );
        _updateLiquidity__scenario__maxLong(
            1e18,
            fixedRate,
            10_000_000_000e18,
            5_000_000_000e18,
            50_000_000e18,
            1
        );

        // Test some concrete values with the max short scenario.
        _updateLiquidity__scenario__maxShort(
            10e6,
            fixedRate,
            100_000_000_000e6,
            50_000_000_000e6,
            50_000_000_000e6,
            1e12
        );
        _updateLiquidity__scenario__maxShort(
            1e15,
            fixedRate,
            200_000_000e18,
            100_000_000e18,
            100_000_000e18,
            1
        );
        _updateLiquidity__scenario__maxShort(
            10e18,
            fixedRate,
            100_000_000_000e18,
            50_000_000_000e18,
            50_000_000_000e18,
            1
        );
    }

    // TODO: The `calculateMaxLong` function isn't reliable enough to fuzz over
    // the fixed rate in this test. Once we've updated the `calculateMaxLong`
    // function based on Spearbit's suggestions, we should give generalizing
    // this another try.
    //
    // This test fuzzes scenarios for `_updateLiquidity` with extreme values.
    function test__updateLiquidity__extremeValues__fuzz(
        uint256 _contribution,
        uint256 _longAmount,
        uint256 _shortAmount
    ) external {
        uint256 fixedRate = 0.05e18;

        // Validate the safe bounds for a minimum share reserves of 10e6. This
        // is a suitable default for USDC pools that supports pool total
        // supplies up to 100 billion USDC.
        {
            uint256 minimumShareReserves = 10e6;

            // Sample the contribution. We simulate the pool being deployed and
            // initialized so that we can calculate the bounds for the longs and
            // shorts.
            uint256 contribution = _contribution.normalizeToRange(
                1_000e6,
                100_000_000_000e6
            );
            IHyperdrive.PoolConfig memory config = testConfig(fixedRate);
            config.minimumShareReserves = minimumShareReserves;
            deploy(deployer, config);
            initialize(alice, fixedRate, contribution);
            uint256 longAmount = _longAmount.normalizeToRange(
                1e6,
                hyperdrive.calculateMaxLong(15)
            );
            uint256 shortAmount = _shortAmount.normalizeToRange(
                1e6,
                hyperdrive.calculateMaxShort()
            );

            // Run the scenario tests.
            _updateLiquidity__scenario__maxLong(
                minimumShareReserves,
                fixedRate,
                contribution,
                longAmount,
                shortAmount,
                1e12
            );
            _updateLiquidity__scenario__maxShort(
                minimumShareReserves,
                fixedRate,
                contribution,
                longAmount,
                shortAmount,
                1e12
            );
        }

        // Validate the safe bounds for a minimum share reserves of 1e15. This
        // is a suitable default for ETH pools that supports pool total
        // supplies up to 200 million ETH
        {
            uint256 minimumShareReserves = 1e15;

            // Sample the contribution. We simulate the pool being deployed and
            // initialized so that we can calculate the bounds for the longs and
            // shorts.
            uint256 contribution = _contribution.normalizeToRange(
                1e18,
                200_000_000e18
            );
            IHyperdrive.PoolConfig memory config = testConfig(fixedRate);
            config.minimumShareReserves = minimumShareReserves;
            deploy(deployer, config);
            initialize(alice, fixedRate, contribution);
            uint256 longAmount = _longAmount.normalizeToRange(
                0.000_1e18,
                hyperdrive.calculateMaxLong()
            );
            uint256 shortAmount = _shortAmount.normalizeToRange(
                0.000_1e18,
                hyperdrive.calculateMaxShort()
            );

            // Run the scenario tests.
            _updateLiquidity__scenario__maxLong(
                minimumShareReserves,
                fixedRate,
                contribution,
                longAmount,
                shortAmount,
                1e6
            );
            _updateLiquidity__scenario__maxShort(
                minimumShareReserves,
                fixedRate,
                contribution,
                longAmount,
                shortAmount,
                1e6
            );
        }

        // Validate the safe bounds for a minimum share reserves of 1e18. This
        // is a suitable default for DAI pools and pools with other stablecoins.
        // It supports pool total supplies up to 100 billion DAI.
        {
            uint256 minimumShareReserves = 10e18;

            // Sample the contribution. We simulate the pool being deployed and
            // initialized so that we can calculate the bounds for the longs and
            // shorts.
            uint256 contribution = _contribution.normalizeToRange(
                1_000e18,
                100_000_000_000e18
            );
            IHyperdrive.PoolConfig memory config = testConfig(fixedRate);
            config.minimumShareReserves = minimumShareReserves;
            deploy(deployer, config);
            initialize(alice, fixedRate, contribution);
            uint256 longAmount = _longAmount.normalizeToRange(
                0.000_1e18,
                hyperdrive.calculateMaxLong()
            );
            uint256 shortAmount = _shortAmount.normalizeToRange(
                0.000_1e18,
                hyperdrive.calculateMaxShort()
            );

            // Run the scenario tests.
            _updateLiquidity__scenario__maxLong(
                minimumShareReserves,
                fixedRate,
                contribution,
                longAmount,
                shortAmount,
                10
            );
            _updateLiquidity__scenario__maxShort(
                minimumShareReserves,
                fixedRate,
                contribution,
                longAmount,
                shortAmount,
                10
            );
        }
    }

    // This verifies that the `updateLiquidity` gives the expected result with
    // the provided parameters when a max long is opened right before a position
    // matures. This is verifying that `z_1 * y_0 / z_0` doesn't result in
    // invalid outputs.
    function _updateLiquidity__scenario__maxLong(
        uint256 minimumShareReserves,
        uint256 fixedRate,
        uint256 contribution,
        uint256 longAmount,
        uint256 shortAmount,
        uint256 tolerance
    ) internal {
        // Bob adds liquidity to the pool. Celine front-runs him by opening a
        // max long. After adding liquidity, Bob receives LP shares that are
        // close in value to his contribution (he pays a small penalty for
        // hurting the trader's profit and loss). This tests the edge case where
        // `z_1 > z_0` and `y_0` is very large.
        {
            // Deploy the pool with the specified minimum share reserves.
            IHyperdrive.PoolConfig memory config = testConfig(fixedRate);
            config.minimumShareReserves = minimumShareReserves;
            deploy(deployer, config);

            // Alice initializes the pool.
            initialize(alice, fixedRate, contribution);

            // Celine opens a max long.
            // TODO: Using a high number of max iterations because of the issues
            // with a wide range of parameters. We should be able to lower this
            // after https://github.com/spearbit-audits/review-element/issues/65
            // is addressed.
            openLong(celine, hyperdrive.calculateMaxLong(15).mulDown(0.9e18));

            // TODO: When we address the issue related to sandwiching large
            // shorts around adding liquidity, we should tighten this bound.
            //
            // Bob adds liquidity. He should receive LP shares that are close
            // to the value of his contribution.
            uint256 lpShares = addLiquidity(bob, contribution);
            assertGt(
                lpShares.mulDown(hyperdrive.lpSharePrice()),
                contribution.mulDown(0.9e18)
            );
            assertGt(lpShares, contribution.mulDown(0.9e18));
        }

        // Bob opens a long and holds it for almost the entire term. Before
        // the long matures, Celine opens a max short. After Bob's position
        // matures, Bob should be able to close his position. This tests the
        // edge case where `z_1 < z_0` and `y_0` is very small.
        {
            // Deploy the pool with the specified minimum share reserves.
            IHyperdrive.PoolConfig memory config = testConfig(fixedRate);
            config.minimumShareReserves = minimumShareReserves;
            deploy(deployer, config);

            // Alice initializes the pool.
            initialize(alice, fixedRate, contribution);

            // Bob opens a long.
            (uint256 maturityTime0, ) = openLong(bob, longAmount);

            // Most of the term passes.
            advanceTime(POSITION_DURATION.mulDown(0.99e18), 0);

            // Celine opens a max long.
            openLong(celine, hyperdrive.calculateMaxLong(15).mulDown(0.9e18));

            // The rest of the term passes.
            advanceTime(POSITION_DURATION.mulDown(0.1e18), 0);

            // Verify that the ending bond reserves are greater than zero and
            // that the ending spot rate is the same as it was before the trade
            // is closed.
            uint256 aprBefore = hyperdrive.calculateAPRFromReserves();
            closeLong(bob, maturityTime0, longAmount);
            assertApproxEqAbs(
                hyperdrive.calculateAPRFromReserves(),
                aprBefore,
                tolerance
            );
            assertGt(hyperdrive.getPoolInfo().bondReserves, 0);
        }

        // Bob opens a short and holds it for almost the entire term. Before
        // the short matures, Celine opens a max short. After Bob's position
        // matures, Bob should be able to close his position. This tests the
        // edge case where `z_1 > z_0` and `y_0` is very small.
        {
            // Deploy the pool with the specified minimum share reserves.
            IHyperdrive.PoolConfig memory config = testConfig(fixedRate);
            config.minimumShareReserves = minimumShareReserves;
            deploy(deployer, config);

            // Alice initializes the pool.
            initialize(alice, fixedRate, contribution);

            // Bob opens a short.
            (uint256 maturityTime0, ) = openShort(bob, shortAmount);

            // Most of the term passes.
            advanceTime(POSITION_DURATION.mulDown(0.99e18), 0);

            // Celine opens a max long.
            openLong(celine, hyperdrive.calculateMaxLong(15).mulDown(0.9e18));

            // The rest of the term passes.
            advanceTime(POSITION_DURATION.mulDown(0.1e18), 0);

            // Verify that the ending bond reserves are greater than zero and
            // that the ending spot rate is the same as it was before the trade
            // is closed.
            uint256 aprBefore = hyperdrive.calculateAPRFromReserves();
            closeShort(bob, maturityTime0, shortAmount);
            assertApproxEqAbs(
                hyperdrive.calculateAPRFromReserves(),
                aprBefore,
                tolerance
            );
            assertGt(hyperdrive.getPoolInfo().bondReserves, 0);
        }
    }

    // This verifies that the `updateLiquidity` doesn't overflow with the
    // provided parameters when a max short is opened right before a position
    // matures. This is verifying that `z_1 * y_0 / z_0` doesn't overflow.
    function _updateLiquidity__scenario__maxShort(
        uint256 minimumShareReserves,
        uint256 fixedRate,
        uint256 contribution,
        uint256 longAmount,
        uint256 shortAmount,
        uint256 tolerance
    ) internal {
        // Bob adds liquidity to the pool. Celine front-runs him by opening a
        // max short. After adding liquidity, Bob a reasonable present value.
        // This tests the edge case where `z_1 > z_0` and `y_0` is very large.
        {
            // Deploy the pool with the specified minimum share reserves.
            IHyperdrive.PoolConfig memory config = testConfig(fixedRate);
            config.minimumShareReserves = minimumShareReserves;
            deploy(deployer, config);

            // Alice initializes the pool.
            initialize(alice, fixedRate, contribution);

            // Celine opens a max short.
            openShort(celine, hyperdrive.calculateMaxShort().mulDown(0.9e18));

            // TODO: When we address the issue related to sandwiching large
            // shorts around adding liquidity, we should tighten this bound.
            //
            // Bob adds liquidity. He should receive LP shares that are close
            // to the value of his contribution.
            uint256 lpShares = addLiquidity(bob, contribution);
            assertGt(
                lpShares.mulDown(hyperdrive.lpSharePrice()),
                contribution.mulDown(0.9e18)
            );
            assertGt(lpShares, contribution.mulDown(0.9e18));
        }

        // Bob opens a long and holds it for almost the entire term. Before
        // the long matures, Celine opens a max short. After Bob's position
        // matures, Bob should be able to close his position. This tests the
        // edge case where `z_1 < z_0` and `y_0` is very large.
        {
            // Deploy the pool with the specified minimum share reserves.
            IHyperdrive.PoolConfig memory config = testConfig(fixedRate);
            config.minimumShareReserves = minimumShareReserves;
            deploy(deployer, config);

            // Alice initializes the pool.
            initialize(alice, fixedRate, contribution);

            // Bob opens a long.
            (uint256 maturityTime0, ) = openLong(bob, longAmount);

            // Most of the term passes.
            advanceTime(POSITION_DURATION.mulDown(0.99e18), 0);

            // Celine opens a max short.
            openShort(celine, hyperdrive.calculateMaxShort().mulDown(0.9e18));

            // The rest of the term passes.
            advanceTime(POSITION_DURATION.mulDown(0.1e18), 0);

            // Verify that the ending bond reserves are greater than zero and
            // that the ending spot rate is the same as it was before the trade
            // is closed.
            uint256 aprBefore = hyperdrive.calculateAPRFromReserves();
            closeLong(bob, maturityTime0, longAmount);
            assertApproxEqAbs(
                hyperdrive.calculateAPRFromReserves(),
                aprBefore,
                tolerance
            );
            assertGt(hyperdrive.getPoolInfo().bondReserves, 0);
        }

        // Bob opens a short and holds it for almost the entire term. Before
        // the short matures, Celine opens a max short. After Bob's position
        // matures, Bob should be able to close his position. This tests the
        // edge case where `z_1 > z_0` and `y_0` is very large.
        {
            // Deploy the pool with the specified minimum share reserves.
            IHyperdrive.PoolConfig memory config = testConfig(fixedRate);
            config.minimumShareReserves = minimumShareReserves;
            deploy(deployer, config);

            // Alice initializes the pool.
            initialize(alice, fixedRate, contribution);

            // Bob opens a short.
            (uint256 maturityTime0, ) = openShort(bob, shortAmount);

            // Most of the term passes.
            advanceTime(POSITION_DURATION.mulDown(0.99e18), 0);

            // Celine opens a max short.
            openShort(celine, hyperdrive.calculateMaxShort().mulDown(0.9e18));

            // The rest of the term passes.
            advanceTime(POSITION_DURATION.mulDown(0.1e18), 0);

            // Verify that the ending bond reserves are greater than zero and
            // that the ending spot rate is the same as it was before the trade
            // is closed.
            uint256 aprBefore = hyperdrive.calculateAPRFromReserves();
            closeShort(bob, maturityTime0, shortAmount);
            assertApproxEqAbs(
                hyperdrive.calculateAPRFromReserves(),
                aprBefore,
                tolerance
            );
            assertGt(hyperdrive.getPoolInfo().bondReserves, 0);
        }
    }
}
