// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "test/utils/HyperdriveTest.sol";
import { Lib } from "test/utils/Lib.sol";

contract PriceDiscoveryTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for *;
    using Lib for *;

    function test_solvency_at_0_apr(
        uint256 fixedAPR,
        uint256 initialContribution,
        uint256 addLiquidityContribution
    ) external {
        uint256 minimumShareReserves = 10e18;

        // Normalize the fuzzing parameters to a reasonable range.
        fixedAPR = fixedAPR.normalizeToRange(0.01e18, 2e18);
        uint256 timeStretchAPR = fixedAPR / 4;
        timeStretchAPR = timeStretchAPR.max(0.01e18);
        timeStretchAPR = timeStretchAPR.min(0.3e18);
        initialContribution = initialContribution.normalizeToRange(
            10_000e18,
            100_000_000e18
        );
        addLiquidityContribution = addLiquidityContribution.normalizeToRange(
            1e18,
            100_000_000e18
        );

        // Configure the pool.
        IHyperdrive.PoolConfig memory config = testConfig(
            timeStretchAPR,
            POSITION_DURATION
        );
        config.circuitBreakerDelta = type(uint128).max;
        config.minimumShareReserves = minimumShareReserves;
        deploy(alice, config);
        vm.stopPrank();
        vm.startPrank(alice);
        baseToken.mint(initialContribution);
        baseToken.approve(address(hyperdrive), initialContribution);
        hyperdrive.initialize(
            initialContribution,
            fixedAPR,
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Alice opens a max long.
        openLong(alice, hyperdrive.calculateMaxLong());
        assertApproxEqAbs(hyperdrive.calculateSpotAPR(), 0, 100 wei);

        // Alice adds liquidity again
        addLiquidity(alice, addLiquidityContribution);

        uint256 sharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
        uint256 shareReserves = hyperdrive.getPoolInfo().shareReserves;
        uint256 longExposure = hyperdrive.getPoolInfo().longExposure;
        int256 solvency = int256(shareReserves.mulDown(sharePrice)) -
            int256(longExposure) -
            int256(2 * minimumShareReserves.mulDown(sharePrice));
        assertTrue(solvency > 0);
    }

    function test_solvency_cross_checkpoint_long_short(
        uint256 fixedAPR,
        uint256 initialContribution,
        uint256 addLiquidityContribution,
        uint256 longAmount,
        uint256 shortAmount,
        bool longFirst
    ) external {
        uint256 minimumShareReserves = 10e18;

        // Normalize the fuzzing parameters to a reasonable range.
        fixedAPR = fixedAPR.normalizeToRange(0.01e18, 2e18);
        uint256 timeStretchAPR = fixedAPR / 4;
        timeStretchAPR = timeStretchAPR.max(0.01e18);
        timeStretchAPR = timeStretchAPR.min(0.3e18);
        initialContribution = initialContribution.normalizeToRange(
            10_000e18,
            100_000_000e18
        );
        addLiquidityContribution = addLiquidityContribution.normalizeToRange(
            1e18,
            100_000_000e18
        );

        // Configure the pool.
        IHyperdrive.PoolConfig memory config = testConfig(
            timeStretchAPR,
            POSITION_DURATION
        );
        config.circuitBreakerDelta = type(uint128).max;
        config.minimumShareReserves = minimumShareReserves;
        deploy(alice, config);
        vm.stopPrank();
        vm.startPrank(alice);
        baseToken.mint(initialContribution);
        baseToken.approve(address(hyperdrive), initialContribution);
        hyperdrive.initialize(
            initialContribution,
            fixedAPR,
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: new bytes(0)
            })
        );

        // Alice opens a max long or a max short.
        if (longFirst) {
            longAmount = longAmount.normalizeToRange(
                2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
                hyperdrive.calculateMaxLong()
            );
            openLong(alice, longAmount);
        } else {
            shortAmount = shortAmount.normalizeToRange(
                2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
                hyperdrive.calculateMaxShort()
            );
            openShort(alice, shortAmount);
        }

        // The checkpoint passes.
        advanceTime(CHECKPOINT_DURATION, 0);

        // Alice opens a max long or a max short.
        if (longFirst) {
            shortAmount = shortAmount.normalizeToRange(
                2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
                hyperdrive.calculateMaxShort()
            );
            openShort(alice, shortAmount);
        } else {
            longAmount = longAmount.normalizeToRange(
                2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
                hyperdrive.calculateMaxLong()
            );
            openLong(alice, longAmount);
        }

        // Alice adds liquidity again
        addLiquidity(alice, addLiquidityContribution);

        // Ensure that the ending solvency isn't negative.
        assertTrue(hyperdrive.solvency() >= 0);
    }

    function test_priceDiscovery_steth_fuzz(
        uint256 initialContribution,
        uint256 addLiquidityContribution1,
        uint256 addLiquidityContribution2
    ) external {
        uint256 timeStretchAPR = 0.035e18;
        uint256 fixedAPR = 0.032e18;
        uint256 minimumShareReserves = 1e15;

        // Normalize the fuzzing parameters to a reasonable range.
        initialContribution = initialContribution.normalizeToRange(
            10e18,
            100_000_000e18
        );
        addLiquidityContribution1 = addLiquidityContribution1.normalizeToRange(
            1e18,
            100_000_000e18
        );
        addLiquidityContribution2 = addLiquidityContribution2.normalizeToRange(
            1e18,
            100_000_000e18
        );

        // Get the high and low spot rates.
        (uint256 highSpotRate, uint256 lowSpotRate, , ) = _test_priceDiscovery(
            timeStretchAPR,
            fixedAPR,
            minimumShareReserves,
            initialContribution,
            addLiquidityContribution1,
            addLiquidityContribution2,
            1e18
        );

        // Test the high and low spot rates.
        assertGt(highSpotRate, lowSpotRate);
        assertGe(highSpotRate, 4 * fixedAPR);
        assertApproxEqAbs(lowSpotRate, 0, 100 wei);
    }

    function test_priceDiscovery_sdai_fuzz(
        uint256 initialContribution,
        uint256 addLiquidityContribution1,
        uint256 addLiquidityContribution2
    ) external {
        uint256 timeStretchAPR = 0.05e18;
        uint256 fixedAPR = 0.08e18;
        uint256 minimumShareReserves = 10e18;

        // Normalize the fuzzing parameters to a reasonable range.
        initialContribution = initialContribution.normalizeToRange(
            100_000e18,
            100_000_000e18
        );
        addLiquidityContribution1 = addLiquidityContribution1.normalizeToRange(
            1e18,
            100_000_000e18
        );
        addLiquidityContribution2 = addLiquidityContribution2.normalizeToRange(
            1e18,
            100_000_000e18
        );

        // Get the high and low spot rates.
        (uint256 highSpotRate, uint256 lowSpotRate, , ) = _test_priceDiscovery(
            timeStretchAPR,
            fixedAPR,
            minimumShareReserves,
            initialContribution,
            addLiquidityContribution1,
            addLiquidityContribution2,
            1e18
        );

        // Test the high and low spot rates.
        assertGt(highSpotRate, lowSpotRate);
        assertGe(highSpotRate, 4 * fixedAPR);
        assertApproxEqAbs(lowSpotRate, 0, 100 wei);
    }

    // This test fuzzes over the full range of inputs, but
    // only verifies that the low spot rate is approximately 0.
    function test_priceDiscovery_full_range_fuzz(
        uint256 fixedAPR,
        uint256 timeStretchAPR,
        uint256 initialContribution,
        uint256 addLiquidityContribution1,
        uint256 addLiquidityContribution2
    ) external {
        uint256 minimumShareReserves = 10e18;

        // Normalize the fuzzing parameters to a reasonable range.
        fixedAPR = fixedAPR.normalizeToRange(0.01e18, 2e18);
        timeStretchAPR = fixedAPR / 4;
        timeStretchAPR = timeStretchAPR.max(0.01e18);
        timeStretchAPR = timeStretchAPR.min(0.3e18);
        initialContribution = initialContribution.normalizeToRange(
            10_000e18,
            100_000_000e18
        );
        addLiquidityContribution1 = addLiquidityContribution1.normalizeToRange(
            1e18,
            100_000_000e18
        );
        addLiquidityContribution2 = addLiquidityContribution2.normalizeToRange(
            1e18,
            100_000_000e18
        );

        // Get the high and low spot rates.
        // Note: This test fuzzes over a larger fixedAPR range and
        // as a result some large APRs cause maxShort to fail. As a
        // result, we pass in a maxShortLimiter of 99% to avoid this.
        (
            uint256 highSpotRate,
            uint256 lowSpotRate,
            bytes memory initError,
            bytes memory addLiquidityError
        ) = _test_priceDiscovery(
                fixedAPR,
                timeStretchAPR,
                minimumShareReserves,
                initialContribution,
                addLiquidityContribution1,
                addLiquidityContribution2,
                0.99e18
            );
        if (initError.length == 0 && addLiquidityError.length == 0) {
            // Test the high and low spot rates.
            assertGt(highSpotRate, lowSpotRate);
            assertApproxEqAbs(lowSpotRate, 0, 100 wei);
        } else if (initError.length == 0 && addLiquidityError.length > 0) {
            // Verify that error is CircuitBreakerTriggered IHyperdrive.MinimumTransactionAmount.
            if (
                keccak256(abi.encodePacked(addLiquidityError)) ==
                keccak256(
                    abi.encodePacked(
                        IHyperdrive.CircuitBreakerTriggered.selector
                    )
                )
            ) {
                // The circuit breaker was triggered as intended.
                assertTrue(true);
            } else if (
                keccak256(abi.encodePacked(addLiquidityError)) ==
                keccak256(
                    abi.encodePacked(
                        IHyperdrive.MinimumTransactionAmount.selector
                    )
                )
            ) {
                // The minimum transaction amount was triggered bc the contribution was so low compared to the existing lp shares.
                assertTrue(true);
            } else if (
                keccak256(abi.encodePacked(addLiquidityError)) ==
                keccak256(
                    abi.encodePacked(
                        IHyperdrive
                            .DecreasedPresentValueWhenAddingLiquidity
                            .selector
                    )
                )
            ) {
                // The present value decreased when adding liquidity.
                assertTrue(true);
            } else if (
                keccak256(abi.encodePacked(addLiquidityError)) ==
                keccak256(
                    abi.encodePacked(IHyperdrive.InvalidPresentValue.selector)
                )
            ) {
                // The effective share reserves were invalid.
                assertTrue(true);
            } else {
                assertTrue(false);
            }
        } else if (initError.length > 0 && addLiquidityError.length == 0) {
            // Verify that error is InvalidEffectiveShareReserves due to mismatched fixedAPR and timeStretchAPR.
            assertEq(
                string(abi.encodePacked(initError)),
                string(
                    abi.encodePacked(
                        IHyperdrive.InvalidEffectiveShareReserves.selector
                    )
                )
            );
        } else {
            // This condition doesn't make sense. It should never happen.
            assertTrue(false);
        }
    }

    // This test fuzzes over the partial range of inputs, but
    // verifies that the low spot rate is approximately 0 and
    // that the high spot rate >= initial rate.
    function test_priceDiscovery_partial_range_fuzz(
        uint256 fixedAPR,
        uint256 timeStretchAPR,
        uint256 initialContribution,
        uint256 addLiquidityContribution1,
        uint256 addLiquidityContribution2
    ) external {
        uint256 minimumShareReserves = 10e18;

        // Normalize the fuzzing parameters to a reasonable range.
        fixedAPR = fixedAPR.normalizeToRange(0.01e18, 1e18);
        timeStretchAPR = fixedAPR / 4;
        timeStretchAPR = timeStretchAPR.max(0.01e18);
        timeStretchAPR = timeStretchAPR.min(0.3e18);
        initialContribution = initialContribution.normalizeToRange(
            10_000e18,
            100_000_000e18
        );
        addLiquidityContribution1 = addLiquidityContribution1.normalizeToRange(
            1e18,
            100_000_000e18
        );
        addLiquidityContribution2 = addLiquidityContribution2.normalizeToRange(
            1e18,
            100_000_000e18
        );

        // Get the high and low spot rates.
        (
            uint256 highSpotRate,
            uint256 lowSpotRate,
            bytes memory initError,
            bytes memory addLiquidityError
        ) = _test_priceDiscovery(
                fixedAPR,
                timeStretchAPR,
                minimumShareReserves,
                initialContribution,
                addLiquidityContribution1,
                addLiquidityContribution2,
                1e18
            );
        if (initError.length == 0 && addLiquidityError.length == 0) {
            // Test the high and low spot rates.
            assertGt(highSpotRate, lowSpotRate);
            assertApproxEqAbs(lowSpotRate, 0, 100 wei);

            // Only test this rule of thumb if the initial contribution is large enough to support
            // high rate discovery after the LP messes with the rate by adding liquidity at a high rate.
            if (
                initialContribution >=
                addLiquidityContribution1 + addLiquidityContribution2
            ) {
                assertGe(highSpotRate, fixedAPR);
            }
        } else if (initError.length == 0 && addLiquidityError.length > 0) {
            // Verify that error is CircuitBreakerTriggered IHyperdrive.MinimumTransactionAmount.
            if (
                keccak256(abi.encodePacked(addLiquidityError)) ==
                keccak256(
                    abi.encodePacked(
                        IHyperdrive.CircuitBreakerTriggered.selector
                    )
                )
            ) {
                // The circuit breaker was triggered as intended.
                assertTrue(true);
            } else if (
                keccak256(abi.encodePacked(addLiquidityError)) ==
                keccak256(
                    abi.encodePacked(
                        IHyperdrive.MinimumTransactionAmount.selector
                    )
                )
            ) {
                // The minimum transaction amount was triggered bc the contribution was so low compared to the existing lp shares.
                assertTrue(true);
            } else if (
                keccak256(abi.encodePacked(addLiquidityError)) ==
                keccak256(
                    abi.encodePacked(
                        IHyperdrive
                            .DecreasedPresentValueWhenAddingLiquidity
                            .selector
                    )
                )
            ) {
                // The present value decreased when adding liquidity.
                assertTrue(true);
            } else if (
                keccak256(abi.encodePacked(addLiquidityError)) ==
                keccak256(
                    abi.encodePacked(IHyperdrive.InvalidPresentValue.selector)
                )
            ) {
                // The effective share reserves were invalid.
                assertTrue(true);
            } else {
                assertTrue(false);
            }
        } else if (initError.length > 0 && addLiquidityError.length == 0) {
            // Verify that error is InvalidEffectiveShareReserves due to mismatched fixedAPR and timeStretchAPR.
            assertEq(
                string(abi.encodePacked(initError)),
                string(
                    abi.encodePacked(
                        IHyperdrive.InvalidEffectiveShareReserves.selector
                    )
                )
            );
        } else {
            // This condition should never happen.
            assertTrue(false);
        }
    }

    function _test_priceDiscovery(
        uint256 fixedAPR,
        uint256 timeStretchAPR,
        uint256 minimumShareReserves,
        uint256 initialContribution,
        uint256 addLiquidityContribution1,
        uint256 addLiquidityContribution2,
        uint256 maxShortLimiter
    )
        internal
        returns (
            uint256 highSpotRate,
            uint256 lowSpotRate,
            bytes memory initError,
            bytes memory addLiquidityError
        )
    {
        IHyperdrive.PoolConfig memory config = testConfig(
            timeStretchAPR,
            POSITION_DURATION
        );
        config.circuitBreakerDelta = type(uint128).max;
        config.minimumShareReserves = minimumShareReserves;
        deploy(alice, config);
        vm.stopPrank();
        vm.startPrank(alice);
        baseToken.mint(initialContribution);
        baseToken.approve(address(hyperdrive), initialContribution);
        try
            hyperdrive.initialize(
                initialContribution,
                fixedAPR,
                IHyperdrive.Options({
                    destination: alice,
                    asBase: true,
                    extraData: new bytes(0)
                })
            )
        {
            // Alice opens a max short.
            openShort(
                alice,
                hyperdrive.calculateMaxShort().mulDown(maxShortLimiter)
            );

            // Alice adds liquidity.
            vm.stopPrank();
            vm.startPrank(alice);
            baseToken.mint(addLiquidityContribution1);
            baseToken.approve(address(hyperdrive), addLiquidityContribution1);
            try
                hyperdrive.addLiquidity(
                    addLiquidityContribution1,
                    0, // min lp share price
                    0, // min spot rate
                    type(uint256).max, // max spot rate
                    IHyperdrive.Options({
                        destination: alice,
                        asBase: true,
                        extraData: new bytes(0)
                    })
                )
            {
                openLong(alice, hyperdrive.calculateMaxLong());

                // The term passes.
                advanceTime(POSITION_DURATION, 0);

                // Alice opens a max short again.
                openShort(
                    alice,
                    hyperdrive.calculateMaxShort().mulDown(maxShortLimiter)
                );

                // Alice adds liquidity again.
                vm.stopPrank();
                vm.startPrank(alice);
                baseToken.mint(addLiquidityContribution2);
                baseToken.approve(
                    address(hyperdrive),
                    addLiquidityContribution2
                );
                try
                    hyperdrive.addLiquidity(
                        addLiquidityContribution2,
                        0, // min lp share price
                        0, // min spot rate
                        type(uint256).max, // max spot rate
                        IHyperdrive.Options({
                            destination: alice,
                            asBase: true,
                            extraData: new bytes(0)
                        })
                    )
                {
                    highSpotRate = hyperdrive.calculateSpotAPR();

                    // Alice opens a max long again.
                    uint256 maxLong = hyperdrive.calculateMaxLong();
                    openLong(alice, maxLong);
                    lowSpotRate = hyperdrive.calculateSpotAPR();
                } catch (bytes memory data) {
                    addLiquidityError = data;
                }
            } catch (bytes memory data) {
                addLiquidityError = data;
            }
        } catch (bytes memory data) {
            initError = data;
        }
    }

    // This edge case demonstrates that an LP can add liquidity if the
    // additional liquidity improves price discovery even when price discovery
    // has been partially compromised by trading.
    function test_priceDiscovery_successEdgeCase() external {
        // Deploy and initialize the pool.
        IHyperdrive.PoolConfig memory config = testConfig(
            0.05e18,
            POSITION_DURATION
        );
        config.circuitBreakerDelta = type(uint128).max;
        config.minimumShareReserves = 10e18;
        deploy(alice, config);
        initialize(alice, 0.05e18, 100_000e18);

        // Open a long.
        openLong(alice, hyperdrive.calculateMaxLong().mulDown(0.9e18));

        // Advance the checkpoint.
        advanceTime(CHECKPOINT_DURATION, 0);

        // Open a short.
        openShort(alice, hyperdrive.calculateMaxShort().mulDown(0.9e18));

        // Advance the checkpoint.
        advanceTime(CHECKPOINT_DURATION, 0);

        // Open a long.
        openLong(alice, hyperdrive.calculateMaxLong());

        // Advance the checkpoint.
        advanceTime(CHECKPOINT_DURATION, 0);

        // Open a short.
        openShort(alice, hyperdrive.calculateMaxShort());

        // Advance the checkpoint.
        advanceTime(CHECKPOINT_DURATION, 0);
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint(), 0);

        // Add liquidity.
        addLiquidity(alice, 100e18);
    }

    // This edge case demonstrates that an LP can't add liquidity if the
    // additional liquidity makes price discovery worse. This demonstrates an
    // extreme example of how to hinder price discovery if the price discvoery
    // checks are removed from `addLiquidity`.
    function test_priceDiscovery_failureEdgeCase() external {
        // Alice deploys and initializes the pool.
        uint256 timeStretchAPR = 0.2e18;
        uint256 fixedAPR = 0.05e18;
        uint256 contribution = 100_000e18;
        IHyperdrive.PoolConfig memory config = testConfig(
            timeStretchAPR,
            POSITION_DURATION
        );
        config.circuitBreakerDelta = type(uint128).max;
        deploy(alice, config);
        initialize(alice, fixedAPR, contribution);

        // Alice opens a max short
        openShort(alice, hyperdrive.calculateMaxShort());
        addLiquidity(alice, contribution);
        openLong(alice, hyperdrive.calculateMaxLong());

        // The term passes.
        advanceTime(POSITION_DURATION, 0);

        // Alice opens a max short.
        openShort(alice, hyperdrive.calculateMaxShort());

        // Alice adds liquidity.
        vm.stopPrank();
        vm.startPrank(alice);
        contribution = 1_000_000e18;
        baseToken.mint(contribution);
        baseToken.approve(address(hyperdrive), contribution);
        vm.expectRevert(IHyperdrive.CircuitBreakerTriggered.selector);
        hyperdrive.addLiquidity(
            contribution,
            0,
            0,
            type(uint256).max,
            IHyperdrive.Options({
                asBase: true,
                destination: alice,
                extraData: new bytes(0)
            })
        );
    }
}
