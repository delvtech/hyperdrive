// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "../../../contracts/src/libraries/YieldSpaceMath.sol";
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
        uint256 apr = hyperdrive.calculateSpotAPR();
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
            hyperdrive.calculateSpotAPR(),
            HyperdriveMath.calculateSpotAPR(
                HyperdriveMath.calculateEffectiveShareReserves(
                    poolInfoAfter.shareReserves,
                    poolInfoAfter.shareAdjustment
                ),
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
        uint256 aprBefore = hyperdrive.calculateSpotAPR();
        openShort(bob, bondAmount);
        uint256 aprAfter = hyperdrive.calculateSpotAPR();

        // Ensure the spot rate increased and that either the share reserves are
        // approximately equal to the minimum share reserves or the pool's
        // solvency is approximately equal to zero.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();
        require(
            HyperdriveMath
                .calculateEffectiveShareReserves(
                    poolInfoAfter.shareReserves,
                    poolInfoAfter.shareAdjustment
                )
                .approxEq(
                    hyperdrive.getPoolConfig().minimumShareReserves,
                    1e10
                ) || hyperdrive.solvency() < 1e15,
            "short amount was not the max short"
        );
        assertGt(aprAfter, aprBefore);

        // Ensure that the bond reserves were updated to have the correct APR.
        assertApproxEqAbs(
            hyperdrive.calculateSpotAPR(),
            HyperdriveMath.calculateSpotAPR(
                HyperdriveMath.calculateEffectiveShareReserves(
                    poolInfoAfter.shareReserves,
                    poolInfoAfter.shareAdjustment
                ),
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
        assertApproxEqAbs(
            hyperdrive.calculateSpotAPR(),
            HyperdriveMath.calculateSpotAPR(
                HyperdriveMath.calculateEffectiveShareReserves(
                    poolInfoAfter.shareReserves,
                    poolInfoAfter.shareAdjustment
                ),
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
        uint256 aprBefore = hyperdrive.calculateSpotAPR();
        openShort(bob, bondAmount);
        uint256 aprAfter = hyperdrive.calculateSpotAPR();

        // Ensure the spot rate increased and that either the share reserves are
        // approximately equal to the minimum share reserves or the pool's
        // solvency is approximately equal to zero.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();
        require(
            HyperdriveMath
                .calculateEffectiveShareReserves(
                    poolInfoAfter.shareReserves,
                    poolInfoAfter.shareAdjustment
                )
                .approxEq(
                    hyperdrive.getPoolConfig().minimumShareReserves,
                    1e10
                ) || hyperdrive.solvency() < 1e15,
            "short amount was not the max short"
        );
        assertGt(aprAfter, aprBefore);

        // Ensure that the bond reserves were updated to have the correct APR.
        // Due to the way that the flat part of the trade is applied, the bond
        // reserve updates may not exactly correspond to the amount of bonds
        // transferred; however, the pool's APR should be identical to the APR
        // that the bond amount transfer implies.
        assertApproxEqAbs(
            hyperdrive.calculateSpotAPR(),
            HyperdriveMath.calculateSpotAPR(
                HyperdriveMath.calculateEffectiveShareReserves(
                    poolInfoAfter.shareReserves,
                    poolInfoAfter.shareAdjustment
                ),
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
        IHyperdrive.PoolConfig memory config = testConfig(
            fixedRate,
            POSITION_DURATION
        );
        config.minimumShareReserves = 1e6;
        config.minimumTransactionAmount = 0.01e6;
        deploy(deployer, config);

        // Alice initializes the pool.
        uint256 contribution = 500_000_000e6;
        initialize(alice, fixedRate, contribution);

        // Bob attempts to short exactly the maximum amount of bonds needed for
        // the share reserves to be equal to zero. This should fail because the
        // share reserves fall below the minimum share reserves.
        IHyperdrive.PoolConfig memory poolConfig = hyperdrive.getPoolConfig();
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        targetReserves = targetReserves.normalizeToRange(
            config.minimumTransactionAmount,
            poolConfig.minimumShareReserves - 1
        );
        uint256 shortAmount = HyperdriveUtils.calculateMaxShort(
            HyperdriveUtils.MaxTradeParams({
                shareReserves: poolInfo.shareReserves,
                shareAdjustment: poolInfo.shareAdjustment,
                bondReserves: poolInfo.bondReserves,
                longsOutstanding: poolInfo.longsOutstanding,
                longExposure: poolInfo.longExposure,
                timeStretch: poolConfig.timeStretch,
                vaultSharePrice: poolInfo.vaultSharePrice,
                initialVaultSharePrice: poolConfig.initialVaultSharePrice,
                minimumShareReserves: targetReserves,
                curveFee: poolConfig.fees.curve,
                flatFee: poolConfig.fees.flat,
                governanceLPFee: poolConfig.fees.governanceLP
            }),
            hyperdrive.getCheckpointExposure(hyperdrive.latestCheckpoint()),
            7
        );
        baseToken.mint(shortAmount);
        baseToken.approve(address(hyperdrive), shortAmount);
        vm.expectRevert(IHyperdrive.InsufficientLiquidity.selector);
        hyperdrive.openShort(
            shortAmount,
            type(uint256).max,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    // This test stresses the edge cases of the `_updateLiquidity` function
    // with sane values that are expected to be used for the most important
    // Hyperdrive integrations.
    function test__updateLiquidity__extremeValues() external {
        uint256 fixedRate = 0.02e18;

        // Test some concrete values with the max long scenario.
        _updateLiquidity__scenario__maxLong(
            1e3,
            1e6,
            fixedRate,
            100_000_000_000e6,
            5_000_000_000e6,
            5_000_000_000e6,
            1e12
        );
        _updateLiquidity__scenario__maxLong(
            1e15,
            1e6,
            fixedRate,
            200_000_000e18,
            50_000_000e18,
            50_000_000e18,
            1
        );
        _updateLiquidity__scenario__maxLong(
            1e15,
            1e6,
            fixedRate,
            10_000_000_000e18,
            2_000_000_000e18,
            50_000_000e18,
            1
        );

        // Test some concrete values with the max short scenario.
        _updateLiquidity__scenario__maxShort(
            1e3,
            1e6,
            fixedRate,
            100_000_000_000e6,
            20_000_000_000e6,
            20_000_000_000e6,
            1e12
        );
        _updateLiquidity__scenario__maxShort(
            1e15,
            1e6,
            fixedRate,
            200_000_000e18,
            50_000_000e18,
            50_000_000e18,
            1
        );
        _updateLiquidity__scenario__maxShort(
            1e15,
            1e6,
            fixedRate,
            100_000_000_000e18,
            20_000_000_000e18,
            20_000_000_000e18,
            1
        );
    }

    function test__updateLiquidity__extremeValues__edge__cases() external {
        // This case was producing a negative interest scenario
        {
            uint256 _contribution = 2;
            uint256 _longAmount = 318204937845433734669313703911115021556041036123016686971127925694678014140;
            uint256 _shortAmount = 0;
            _test__updateLiquidity__extremeValues__fuzz(
                _contribution,
                _longAmount,
                _shortAmount
            );
        }

        // This cases produced a failure due to the input being less than the
        // minimum transaction amount.
        {
            uint256 _contribution = 13083;
            uint256 _longAmount = 115792089237316192247082740042611018616959225516561624832306239692771187490815;
            uint256 _shortAmount = 7865494169775540955914006602;
            _test__updateLiquidity__extremeValues__fuzz(
                _contribution,
                _longAmount,
                _shortAmount
            );
        }
    }

    /// forge-config: default.fuzz.runs = 100
    function test__updateLiquidity__extremeValues__fuzz(
        uint256 _contribution,
        uint256 _longAmount,
        uint256 _shortAmount
    ) external {
        _test__updateLiquidity__extremeValues__fuzz(
            _contribution,
            _longAmount,
            _shortAmount
        );
    }

    // TODO: The `calculateMaxLong` function isn't reliable enough to fuzz over
    // the fixed rate in this test. Once we've updated the `calculateMaxLong`
    // function based on Spearbit's suggestions, we should give generalizing
    // this another try.
    //
    // This test fuzzes scenarios for `_updateLiquidity` with extreme values.
    function _test__updateLiquidity__extremeValues__fuzz(
        uint256 _contribution,
        uint256 _longAmount,
        uint256 _shortAmount
    ) internal {
        uint256 fixedRate = 0.05e18;

        // Validate the safe bounds for a minimum share reserves of 1e3 and
        // a minimum transaction amount of 0.1e6. This
        // is a suitable default for USDC pools that supports pool total
        // supplies up to 100 billion USDC.
        {
            uint256 minimumShareReserves = 1e3;
            uint256 minimumTransactionAmount = 0.1e6;

            // Sample the contribution. We simulate the pool being deployed and
            // initialized so that we can calculate the bounds for the longs and
            // shorts.
            uint256 contribution = _contribution.normalizeToRange(
                1_000e6,
                100_000_000_000e6
            );
            IHyperdrive.PoolConfig memory config = testConfig(
                fixedRate,
                POSITION_DURATION
            );
            config.minimumShareReserves = minimumShareReserves;
            config.minimumTransactionAmount = minimumTransactionAmount;
            deploy(deployer, config);
            initialize(alice, fixedRate, contribution);
            uint256 longAmount = _longAmount.normalizeToRange(
                minimumTransactionAmount,
                hyperdrive.calculateMaxLong(15) - minimumTransactionAmount
            );
            uint256 shortAmount = _shortAmount.normalizeToRange(
                minimumTransactionAmount,
                hyperdrive.calculateMaxShort() - minimumTransactionAmount
            );

            // Run the scenario tests.
            _updateLiquidity__scenario__maxLong(
                minimumShareReserves,
                minimumTransactionAmount,
                fixedRate,
                contribution,
                longAmount,
                shortAmount,
                1e12
            );
            _updateLiquidity__scenario__maxShort(
                minimumShareReserves,
                minimumTransactionAmount,
                fixedRate,
                contribution,
                longAmount,
                shortAmount,
                1e12
            );
        }

        // Validate the safe bounds for a minimum share reserves of 1e15 and
        // a minimum transaction amount of 0.01e15. This
        // is a suitable default for ETH pools that supports pool total
        // supplies up to 200 million ETH
        {
            uint256 minimumShareReserves = 1e15;
            uint256 minimumTransactionAmount = .01e15;

            // Sample the contribution. We simulate the pool being deployed and
            // initialized so that we can calculate the bounds for the longs and
            // shorts.
            uint256 contribution = _contribution.normalizeToRange(
                1e18,
                200_000_000e18
            );
            IHyperdrive.PoolConfig memory config = testConfig(
                fixedRate,
                POSITION_DURATION
            );
            config.minimumShareReserves = minimumShareReserves;
            config.minimumTransactionAmount = minimumTransactionAmount;
            deploy(deployer, config);
            initialize(alice, fixedRate, contribution);

            // Note: Only using 99% of the max long amount to leave room for
            // another trade above the minimum transaction amount threshold.
            uint256 longAmount = _longAmount.normalizeToRange(
                minimumTransactionAmount,
                hyperdrive.calculateMaxLong().mulDown(0.99e18)
            );
            uint256 shortAmount = _shortAmount.normalizeToRange(
                minimumTransactionAmount,
                hyperdrive.calculateMaxShort() - minimumTransactionAmount
            );

            // Run the scenario tests.
            _updateLiquidity__scenario__maxLong(
                minimumShareReserves,
                minimumTransactionAmount,
                fixedRate,
                contribution,
                longAmount,
                shortAmount,
                1e6
            );
            _updateLiquidity__scenario__maxShort(
                minimumShareReserves,
                minimumTransactionAmount,
                fixedRate,
                contribution,
                longAmount,
                shortAmount,
                1e6
            );
        }

        // Validate the safe bounds for a minimum share reserves of 1e15 and
        // a minimum transaction amount of 0.001e18 This
        // is a suitable default for DAI pools and pools with other stablecoins.
        // It supports pool total supplies up to 100 billion DAI.
        {
            uint256 minimumShareReserves = 1e15;
            uint256 minimumTransactionAmount = MINIMUM_TRANSACTION_AMOUNT;

            // Sample the contribution. We simulate the pool being deployed and
            // initialized so that we can calculate the bounds for the longs and
            // shorts.
            uint256 contribution = _contribution.normalizeToRange(
                1_000e18,
                100_000_000_000e18
            );
            IHyperdrive.PoolConfig memory config = testConfig(
                fixedRate,
                POSITION_DURATION
            );
            config.minimumShareReserves = minimumShareReserves;
            config.minimumTransactionAmount = minimumTransactionAmount;
            deploy(deployer, config);
            initialize(alice, fixedRate, contribution);

            // Note: Only using 99% of the max long amount to leave room for
            // another trade above the minimum transaction amount threshold.
            uint256 longAmount = _longAmount.normalizeToRange(
                minimumTransactionAmount,
                hyperdrive.calculateMaxLong().mulDown(0.99e18)
            );
            uint256 shortAmount = _shortAmount.normalizeToRange(
                minimumTransactionAmount,
                hyperdrive.calculateMaxShort() - minimumTransactionAmount
            );

            // Run the scenario tests.
            _updateLiquidity__scenario__maxLong(
                minimumShareReserves,
                minimumTransactionAmount,
                fixedRate,
                contribution,
                longAmount,
                shortAmount,
                10
            );
            _updateLiquidity__scenario__maxShort(
                minimumShareReserves,
                minimumTransactionAmount,
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
        uint256 minimumTransactionAmount,
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
            IHyperdrive.PoolConfig memory config = testConfig(
                fixedRate,
                POSITION_DURATION
            );
            config.minimumShareReserves = minimumShareReserves;
            config.minimumTransactionAmount = minimumTransactionAmount;
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
        // the long matures, Celine opens a max long. After Bob's position
        // matures, Bob should be able to close his position. This tests the
        // edge case where `z_1 < z_0` and `y_0` is very small.
        {
            // Deploy the pool with the specified minimum share reserves.
            IHyperdrive.PoolConfig memory config = testConfig(
                fixedRate,
                POSITION_DURATION
            );
            config.minimumShareReserves = minimumShareReserves;
            config.minimumTransactionAmount = minimumTransactionAmount;
            deploy(deployer, config);

            // Alice initializes the pool.
            initialize(alice, fixedRate, contribution);

            // Bob opens a long.
            (uint256 maturityTime0, uint256 bondAmount) = openLong(
                bob,
                longAmount
            );
            assertGt(bondAmount, 0);

            // Most of the term passes.
            advanceTimeWithCheckpoints2(POSITION_DURATION.mulDown(0.99e18), 0);

            // Celine opens a max long.
            {
                uint256 maxLong = hyperdrive.calculateMaxLong(15).mulDown(
                    0.9e18
                );
                if (maxLong < minimumTransactionAmount) {
                    vm.stopPrank();
                    vm.startPrank(celine);
                    baseToken.mint(celine, maxLong);
                    baseToken.approve(address(hyperdrive), maxLong);
                    vm.expectRevert(
                        IHyperdrive.MinimumTransactionAmount.selector
                    );
                    hyperdrive.openLong(
                        maxLong,
                        0,
                        0,
                        IHyperdrive.Options({
                            destination: bob,
                            asBase: true,
                            extraData: new bytes(0)
                        })
                    );
                } else {
                    openLong(celine, maxLong);
                }
            }

            // The rest of the term passes.
            advanceTimeWithCheckpoints2(POSITION_DURATION.mulDown(0.1e18), 0);

            // Verify that the ending bond reserves are greater than zero and
            // that the ending spot rate is the same as it was before the trade
            // is closed.
            uint256 aprBefore = hyperdrive.calculateSpotAPR();
            closeLong(bob, maturityTime0, longAmount);
            assertApproxEqAbs(
                hyperdrive.calculateSpotAPR(),
                aprBefore,
                tolerance
            );
            assertGt(hyperdrive.getPoolInfo().bondReserves, 0);
        }

        // Bob opens a short and holds it for almost the entire term. Before
        // the short matures, Celine opens a max long. After Bob's position
        // matures, Bob should be able to close his position. This tests the
        // edge case where `z_1 > z_0` and `y_0` is very small.
        {
            // Deploy the pool with the specified minimum share reserves.
            IHyperdrive.PoolConfig memory config = testConfig(
                fixedRate,
                POSITION_DURATION
            );
            config.minimumShareReserves = minimumShareReserves;
            config.minimumTransactionAmount = minimumTransactionAmount;
            deploy(deployer, config);

            // Alice initializes the pool.
            initialize(alice, fixedRate, contribution);

            // Bob opens a short.
            (uint256 maturityTime0, uint256 baseAmount) = openShort(
                bob,
                shortAmount
            );
            assertGt(baseAmount, 0);

            // Most of the term passes.
            advanceTimeWithCheckpoints2(POSITION_DURATION.mulDown(0.99e18), 0);

            // Celine opens a max long.
            {
                uint256 maxLong = hyperdrive.calculateMaxLong(7).mulDown(
                    0.9e18
                );
                if (maxLong < minimumTransactionAmount) {
                    vm.stopPrank();
                    vm.startPrank(celine);
                    baseToken.mint(celine, maxLong);
                    baseToken.approve(address(hyperdrive), maxLong);
                    vm.expectRevert(
                        IHyperdrive.MinimumTransactionAmount.selector
                    );
                    hyperdrive.openLong(
                        maxLong,
                        0,
                        0,
                        IHyperdrive.Options({
                            destination: bob,
                            asBase: true,
                            extraData: new bytes(0)
                        })
                    );
                } else {
                    openLong(celine, maxLong);
                }
            }

            // The rest of the term passes.
            advanceTimeWithCheckpoints2(POSITION_DURATION.mulDown(0.1e18), 0);

            // Verify that the ending bond reserves are greater than zero and
            // that the ending spot rate is the same as it was before the trade
            // is closed.
            uint256 aprBefore = hyperdrive.calculateSpotAPR();
            closeShort(bob, maturityTime0, shortAmount);
            assertApproxEqAbs(
                hyperdrive.calculateSpotAPR(),
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
        uint256 minimumTransactionAmount,
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
            IHyperdrive.PoolConfig memory config = testConfig(
                fixedRate,
                POSITION_DURATION
            );
            config.minimumShareReserves = minimumShareReserves;
            config.minimumTransactionAmount = minimumTransactionAmount;
            deploy(deployer, config);

            // Alice initializes the pool.
            initialize(alice, fixedRate, contribution);

            // Celine opens a max short.
            {
                uint256 maxShort = hyperdrive.calculateMaxShort().mulDown(
                    0.9e18
                );
                if (maxShort < minimumTransactionAmount) {
                    vm.stopPrank();
                    vm.startPrank(celine);
                    baseToken.mint(celine, maxShort);
                    baseToken.approve(address(hyperdrive), maxShort);
                    vm.expectRevert(
                        IHyperdrive.MinimumTransactionAmount.selector
                    );
                    hyperdrive.openShort(
                        maxShort,
                        type(uint256).max,
                        0,
                        IHyperdrive.Options({
                            destination: bob,
                            asBase: true,
                            extraData: new bytes(0)
                        })
                    );
                } else {
                    openShort(celine, maxShort);
                }
            }

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
            IHyperdrive.PoolConfig memory config = testConfig(
                fixedRate,
                POSITION_DURATION
            );
            config.minimumShareReserves = minimumShareReserves;
            config.minimumTransactionAmount = minimumTransactionAmount;
            deploy(deployer, config);

            // Alice initializes the pool.
            initialize(alice, fixedRate, contribution);

            // Bob opens a long.
            (uint256 maturityTime0, uint256 bondAmount) = openLong(
                bob,
                longAmount
            );
            assertGt(bondAmount, 0);

            // Most of the term passes.
            advanceTimeWithCheckpoints2(POSITION_DURATION.mulDown(0.99e18), 0);

            // Celine opens a max short.
            {
                uint256 maxShort = hyperdrive.calculateMaxShort().mulDown(
                    0.9e18
                );
                if (maxShort < minimumTransactionAmount) {
                    vm.stopPrank();
                    vm.startPrank(celine);
                    baseToken.mint(celine, maxShort);
                    baseToken.approve(address(hyperdrive), maxShort);
                    vm.expectRevert(
                        IHyperdrive.MinimumTransactionAmount.selector
                    );
                    hyperdrive.openShort(
                        maxShort,
                        type(uint256).max,
                        0,
                        IHyperdrive.Options({
                            destination: bob,
                            asBase: true,
                            extraData: new bytes(0)
                        })
                    );
                } else {
                    openShort(celine, maxShort);
                }
            }

            // The rest of the term passes.
            advanceTimeWithCheckpoints2(POSITION_DURATION.mulDown(0.1e18), 0);

            // Verify that the ending bond reserves are greater than zero and
            // that the ending spot rate is the same as it was before the trade
            // is closed.
            uint256 aprBefore = hyperdrive.calculateSpotAPR();
            closeLong(bob, maturityTime0, longAmount);
            assertApproxEqAbs(
                hyperdrive.calculateSpotAPR(),
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
            IHyperdrive.PoolConfig memory config = testConfig(
                fixedRate,
                POSITION_DURATION
            );
            config.minimumShareReserves = minimumShareReserves;
            config.minimumTransactionAmount = minimumTransactionAmount;
            deploy(deployer, config);

            // Alice initializes the pool.
            initialize(alice, fixedRate, contribution);

            // Bob opens a short.
            (uint256 maturityTime0, uint256 baseAmount) = openShort(
                bob,
                shortAmount
            );
            assertGt(baseAmount, 0);

            // Most of the term passes.
            advanceTimeWithCheckpoints2(POSITION_DURATION.mulDown(0.99e18), 0);

            // Celine opens a max short.
            {
                uint256 maxShort = hyperdrive.calculateMaxShort().mulDown(
                    0.9e18
                );
                if (maxShort < minimumTransactionAmount) {
                    vm.stopPrank();
                    vm.startPrank(celine);
                    baseToken.mint(celine, maxShort);
                    baseToken.approve(address(hyperdrive), maxShort);
                    vm.expectRevert(
                        IHyperdrive.MinimumTransactionAmount.selector
                    );
                    hyperdrive.openShort(
                        maxShort,
                        type(uint256).max,
                        0,
                        IHyperdrive.Options({
                            destination: bob,
                            asBase: true,
                            extraData: new bytes(0)
                        })
                    );
                } else {
                    openShort(celine, maxShort);
                }
            }

            // The rest of the term passes.
            advanceTimeWithCheckpoints2(POSITION_DURATION.mulDown(0.1e18), 0);

            // Verify that the ending bond reserves are greater than zero and
            // that the ending spot rate is the same as it was before the trade
            // is closed.
            uint256 aprBefore = hyperdrive.calculateSpotAPR();
            closeShort(bob, maturityTime0, shortAmount);
            assertApproxEqAbs(
                hyperdrive.calculateSpotAPR(),
                aprBefore,
                tolerance
            );
            assertGt(hyperdrive.getPoolInfo().bondReserves, 0);
        }
    }
}
