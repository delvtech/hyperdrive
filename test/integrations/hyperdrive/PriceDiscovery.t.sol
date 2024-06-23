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
            addLiquidityContribution2
        );

        // Test the high and low spot rates.
        assertGt(highSpotRate, lowSpotRate);
        assertGe(highSpotRate, 0.15e18);
        assertApproxEqAbs(lowSpotRate, 0, 1 wei);
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
            addLiquidityContribution2
        );

        // Test the high and low spot rates.
        assertGt(highSpotRate, lowSpotRate);
        assertGe(highSpotRate, 0.30e18);
        assertApproxEqAbs(lowSpotRate, 0, 10 wei);
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
                addLiquidityContribution2
            );
        if (initError.length == 0 && addLiquidityError.length == 0) {
            // Test the high and low spot rates.
            assertGt(highSpotRate, lowSpotRate);
            assertApproxEqAbs(lowSpotRate, 0, 100 wei);
        } else if (initError.length == 0 && addLiquidityError.length > 0) {
            // Verify that error is CircuitBreakerTriggered IHyperdrive.MinimumTransactionAmount
            if (
                keccak256(abi.encodePacked(addLiquidityError)) ==
                keccak256(
                    abi.encodePacked(
                        IHyperdrive.CircuitBreakerTriggered.selector
                    )
                )
            ) {
                // The circuit breaker was triggered as intended
                assertTrue(true);
            } else if (
                keccak256(abi.encodePacked(addLiquidityError)) ==
                keccak256(
                    abi.encodePacked(
                        IHyperdrive.MinimumTransactionAmount.selector
                    )
                )
            ) {
                // The minimum transaction amount was triggered bc the contribution was so low compared to the existing lp shares
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
                // The present value decreased when adding liquidity
                assertTrue(true);
            } else if (
                keccak256(abi.encodePacked(addLiquidityError)) ==
                keccak256(
                    abi.encodePacked(IHyperdrive.InvalidPresentValue.selector)
                )
            ) {
                // The effective share reserves were invalid
                assertTrue(true);
            } else {
                assertTrue(false);
            }
        } else if (initError.length > 0 && addLiquidityError.length == 0) {
            // Verify that error is InvalidEffectiveShareReserves due to mismatched fixedAPR and timeStretchAPR
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
    // that the high spot rate > initial rate.
    function test_priceDiscovery_parial_range_fuzz(
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
                addLiquidityContribution2
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
            // Verify that error is CircuitBreakerTriggered IHyperdrive.MinimumTransactionAmount
            if (
                keccak256(abi.encodePacked(addLiquidityError)) ==
                keccak256(
                    abi.encodePacked(
                        IHyperdrive.CircuitBreakerTriggered.selector
                    )
                )
            ) {
                // The circuit breaker was triggered as intended
                assertTrue(true);
            } else if (
                keccak256(abi.encodePacked(addLiquidityError)) ==
                keccak256(
                    abi.encodePacked(
                        IHyperdrive.MinimumTransactionAmount.selector
                    )
                )
            ) {
                // The minimum transaction amount was triggered bc the contribution was so low compared to the existing lp shares
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
                // The present value decreased when adding liquidity
                assertTrue(true);
            } else if (
                keccak256(abi.encodePacked(addLiquidityError)) ==
                keccak256(
                    abi.encodePacked(IHyperdrive.InvalidPresentValue.selector)
                )
            ) {
                // The effective share reserves were invalid
                assertTrue(true);
            } else {
                assertTrue(false);
            }
        } else if (initError.length > 0 && addLiquidityError.length == 0) {
            // Verify that error is InvalidEffectiveShareReserves due to mismatched fixedAPR and timeStretchAPR
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

    function _test_priceDiscovery(
        uint256 fixedAPR,
        uint256 timeStretchAPR,
        uint256 minimumShareReserves,
        uint256 initialContribution,
        uint256 addLiquidityContribution1,
        uint256 addLiquidityContribution2
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
            // alice opens a max short
            openShort(alice, hyperdrive.calculateMaxShort().mulDown(0.99e18));

            // alice adds liquidity
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

                // the term passes
                advanceTime(POSITION_DURATION, 0);

                // alice opens a max short
                openShort(
                    alice,
                    hyperdrive.calculateMaxShort().mulDown(0.99e18)
                );

                // alice adds liquidity again
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

                    // alice opens a max long.
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
}
