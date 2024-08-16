// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract SandwichTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for *;
    using Lib for *;

    function test_sandwich_trades(uint256 apr, uint256 timeDelta) external {
        apr = apr.normalizeToRange(0.01e18, 0.2e18);
        timeDelta = timeDelta.normalizeToRange(0, ONE);

        // Deploy the pool and initialize the market
        {
            uint256 timeStretchApr = 0.05e18;
            deploy(alice, timeStretchApr, 0, 0, 0, 0);
        }
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);
        contribution -= 2 * hyperdrive.getPoolConfig().minimumShareReserves;

        // Bob opens a long.
        uint256 longPaid = hyperdrive.calculateMaxLong().mulDown(0.05e18);
        (uint256 longMaturityTime, uint256 longAmount) = openLong(
            bob,
            longPaid
        );

        // Some of the term passes and interest accrues at the starting APR.
        uint256 timeAdvanced = POSITION_DURATION.mulDown(timeDelta);
        advanceTime(timeAdvanced, int256(apr));

        // Celine opens a short.
        uint256 shortAmount = hyperdrive.calculateMaxShort().mulDown(0.2e18);
        (uint256 shortMaturityTime, ) = openShort(celine, shortAmount);

        // Bob closes his long.
        closeLong(bob, longMaturityTime, longAmount);

        // Celine immediately closes her short.
        closeShort(celine, shortMaturityTime, shortAmount);

        // Ensure the proceeds from the sandwich attack didn't negatively
        // impact the LP. With this in mind, they should have made at least as
        // much money as if no trades had been made and they just collected
        // variable APR.
        (uint256 lpProceeds, ) = removeLiquidity(alice, lpShares);

        // Calculate how much interest has accrued on the initial contribution
        (uint256 contributionPlusInterest, ) = HyperdriveUtils
            .calculateCompoundInterest(contribution, int256(apr), timeAdvanced);
        assertGe(lpProceeds, contributionPlusInterest);
    }

    function test_sandwich_long_trade(uint256 apr, uint256 tradeSize) external {
        // limit the fuzz testing to variableRate's less than or equal to 50%
        apr = apr.normalizeToRange(0.01e18, 0.2e18);

        // ensure a feasible trade size
        tradeSize = tradeSize.normalizeToRange(1_000e18, 10_000_000e18);

        // Deploy the pool and initialize the market
        {
            uint256 timeStretchApr = 0.05e18;
            deploy(alice, timeStretchApr, 0, 0, 0, 0);
        }
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        uint256 shortLoss;
        // Calculate how much profit would be made from a long sandwiched by shorts
        uint256 sandwichProfit;
        {
            // open a short.
            uint256 bondsShorted = tradeSize; //10_000_000e18;
            (uint256 shortMaturityTime, uint256 shortBasePaid) = openShort(
                bob,
                bondsShorted
            );

            // open a long.
            uint256 basePaid = tradeSize; //10_000_000e18;
            (, uint256 bondsReceived) = openLong(bob, basePaid);

            // immediately close short.
            uint256 shortBaseReturned = closeShort(
                bob,
                shortMaturityTime,
                bondsShorted
            );
            shortLoss = shortBasePaid - shortBaseReturned;

            // long profit is the bonds received minus the base paid
            // bc we assume the bonds mature 1:1 to base
            uint256 longProfit = bondsReceived - basePaid;
            sandwichProfit = longProfit - shortLoss;
        }

        // Deploy the pool and initialize the market
        {
            uint256 timeStretchApr = 0.05e18;
            deploy(alice, timeStretchApr, 0, 0, 0, 0);
        }
        initialize(alice, apr, contribution);

        // Calculate how much profit would be made from a simple long
        uint256 baselineProfit;
        {
            // open a long.
            uint256 basePaid = tradeSize;
            basePaid = basePaid + shortLoss;
            (uint256 longMaturityTime, uint256 bondsReceived) = openLong(
                celine,
                basePaid
            );
            closeLong(celine, longMaturityTime, bondsReceived);
            // profit is the bonds received minus the base paid
            // bc we assume the bonds mature 1:1 to base
            baselineProfit = bondsReceived - basePaid;
        }
        assertGe(baselineProfit, sandwichProfit - 10000 gwei);
    }

    function test_sandwich_short_trade(
        uint256 fixedRate,
        uint256 contribution,
        uint256 tradeAmount,
        uint256 sandwichAmount
    ) external {
        _test_sandwich_short_trade(
            fixedRate,
            contribution,
            tradeAmount,
            sandwichAmount
        );
    }

    function test_sandwich_short_trade_edge_cases() external {
        // This test caused the sandwich test to fail because the sandwiching
        // short made a small profit when the curve fee was 0. This was fixed
        // by increasing the curve fee to 0.0001e18.
        {
            uint256 fixedRate = 998962223204933958;
            uint256 contribution = 2042272226342949092412748848311668432195895990698578471431773993;
            uint256 tradeAmount = 1000475753853052421;
            uint256 sandwichAmount = 8174;
            _test_sandwich_short_trade(
                fixedRate,
                contribution,
                tradeAmount,
                sandwichAmount
            );
        }

        // This test caused the sandwich test to fail because the sandwiching
        // short made a small profit when the curve fee was 0. This was fixed
        // by increasing the curve fee to 0.0001e18.
        {
            uint256 fixedRate = 998000000000000060407;
            uint256 contribution = 759073715388587821013812734928096154771786292308418320735217;
            uint256 tradeAmount = 87494182301843377180327349;
            uint256 sandwichAmount = 22746;
            _test_sandwich_short_trade(
                fixedRate,
                contribution,
                tradeAmount,
                sandwichAmount
            );
        }
    }

    function _test_sandwich_short_trade(
        uint256 fixedRate,
        uint256 contribution,
        uint256 tradeAmount,
        uint256 sandwichAmount
    ) internal {
        IHyperdrive.PoolConfig memory config = testConfig(
            0.05e18,
            POSITION_DURATION
        );
        config.fees.curve = 0.0001e18;
        deploy(alice, config);
        fixedRate = fixedRate.normalizeToRange(0.001e18, 0.7e18);
        contribution = contribution.normalizeToRange(
            100_000e18,
            500_000_000e18
        );
        uint256 lpShares = initialize(alice, fixedRate, contribution);
        contribution -= 2 * config.minimumShareReserves;

        // Bob opens a short.
        tradeAmount = tradeAmount.normalizeToRange(
            hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxShort().mulDown(0.9e18)
        );
        openShort(bob, tradeAmount);

        // Most of the term passes and no interest accrues.
        advanceTime(POSITION_DURATION - 12 seconds, 0);

        // Celine opens a short to sandwich the closing of Bob's short.
        sandwichAmount = sandwichAmount.normalizeToRange(
            hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxShort()
        );
        (uint256 maturityTime, uint256 shortPayment) = openShort(
            celine,
            sandwichAmount
        );

        // The rest of the term passes and no interest accrues.
        advanceTime(12 seconds, 0);

        // Celine closes her short. Her short should have been unprofitable.
        uint256 shortProceeds = closeShort(
            celine,
            maturityTime,
            sandwichAmount
        );
        assertLt(shortProceeds, shortPayment);

        // Alice removes her liquidity. She should receive at least as much as
        // as she put in.
        (uint256 withdrawalProceeds, ) = removeLiquidity(alice, lpShares);
        assertGe(withdrawalProceeds, contribution);
    }

    function test_sandwich_lp(uint256 apr) external {
        apr = apr.normalizeToRange(0.01e18, 0.2e18);

        // Deploy the pool with fees.
        {
            uint256 timeStretchApr = 0.05e18;
            uint256 curveFee = 0.001e18;
            deploy(alice, timeStretchApr, curveFee, 0, 0, 0);
        }

        // Initialize the market.
        uint256 contribution = 500_000_000e18;
        uint256 aliceLpShares = initialize(alice, apr, contribution);

        // Bob opens a large long and a short.
        uint256 tradeAmount = 10_000_000e18;
        (uint256 longMaturityTime, uint256 longAmount) = openLong(
            bob,
            tradeAmount
        );
        (uint256 shortMaturityTime, ) = openShort(bob, tradeAmount);

        // Bob adds liquidity. Bob shouldn't receive more LP shares than Alice.
        uint256 bobLpShares = addLiquidity(bob, contribution);
        assertLe(bobLpShares, aliceLpShares);

        // Bob closes his positions.
        closeLong(bob, longMaturityTime, longAmount);
        closeShort(bob, shortMaturityTime, tradeAmount);

        // Bob removes his liquidity.
        removeLiquidity(bob, bobLpShares);

        // Ensure the proceeds from the sandwich attack didn't negatively impact
        // the LP.
        (uint256 lpProceeds, ) = removeLiquidity(alice, aliceLpShares);
        assertGe(lpProceeds, contribution);
    }

    struct TestCase {
        uint256 aliceContribution;
        uint256 aliceLpShares;
        uint256 aliceBaseProceeds;
        uint256 aliceWithdrawalShares;
        uint256 celineContribution;
    }

    function test_sandwich_add_liquidity_short_and_long_high_timestretch(
        uint256 aliceContribution,
        uint256 celineContribution,
        uint256 fixedAPR,
        uint256 timeStretchAPR,
        uint256 variableAPR,
        uint256 shortAmount,
        uint256 longBasePaid
    ) external {
        // Normalize the test parameters.
        aliceContribution = aliceContribution.normalizeToRange(
            10_000e18,
            100_000_000e18
        );
        celineContribution = celineContribution.normalizeToRange(
            10_000e18,
            100_000_000e18
        );
        timeStretchAPR = timeStretchAPR.normalizeToRange(0.05e18, 0.3e18);
        fixedAPR = fixedAPR.normalizeToRange(0.05e18, timeStretchAPR * 2);
        variableAPR = variableAPR.normalizeToRange(fixedAPR, fixedAPR * 2);

        // Run the test.
        _test_sandwich_add_liquidity_short_and_long(
            aliceContribution,
            celineContribution,
            fixedAPR,
            timeStretchAPR,
            variableAPR,
            shortAmount,
            longBasePaid,
            0.075e18 // circuit breaker delta = 7.5%
        );
    }

    function test_sandwich_add_liquidity_short_and_long_low_timestretch(
        uint256 aliceContribution,
        uint256 celineContribution,
        uint256 fixedAPR,
        uint256 timeStretchAPR,
        uint256 variableAPR,
        uint256 shortAmount,
        uint256 longBasePaid
    ) external {
        // Normalize the test parameters.
        aliceContribution = aliceContribution.normalizeToRange(
            10_000e18,
            100_000_000e18
        );
        celineContribution = celineContribution.normalizeToRange(
            10_000e18,
            100_000_000e18
        );
        timeStretchAPR = timeStretchAPR.normalizeToRange(0.01e18, 0.05e18);
        fixedAPR = fixedAPR.normalizeToRange(0.01e18, timeStretchAPR * 2);
        variableAPR = variableAPR.normalizeToRange(fixedAPR, 0.15e18);

        // Run the test.
        _test_sandwich_add_liquidity_short_and_long(
            aliceContribution,
            celineContribution,
            fixedAPR,
            timeStretchAPR,
            variableAPR,
            shortAmount,
            longBasePaid,
            timeStretchAPR // circuit breaker delta = time stretch apr
        );
    }

    // This test ensures that add liquidity sandwiches are limited in scope.
    // In general, these sandwich attacks can result in early LPs losing money,
    // but these vulnerabilities are mitigated by circuit breakers on
    // `addLiquidity`.
    function _test_sandwich_add_liquidity_short_and_long(
        uint256 aliceContribution,
        uint256 celineContribution,
        uint256 fixedAPR,
        uint256 timeStretchAPR,
        uint256 variableAPR,
        uint256 shortAmount,
        uint256 longBasePaid,
        uint256 circuitBreakerDelta
    ) internal {
        // Set up the test case.
        TestCase memory testCase;
        testCase.aliceContribution = aliceContribution;
        testCase.celineContribution = celineContribution;

        // Alice deploys and initializes the pool.
        IHyperdrive.PoolConfig memory config = testConfig(
            timeStretchAPR,
            POSITION_DURATION
        );
        config.fees.curve = 0.01e18;
        config.fees.flat = 0.0005e18;
        config.circuitBreakerDelta = circuitBreakerDelta;
        deploy(alice, config);
        testCase.aliceLpShares = initialize(
            alice,
            fixedAPR,
            testCase.aliceContribution
        );
        testCase.aliceContribution -=
            2 *
            hyperdrive.getPoolConfig().minimumShareReserves;

        // Celine opens a large short.
        shortAmount = shortAmount.normalizeToRange(
            hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxShort()
        );
        openShort(celine, shortAmount);

        // Celine adds liquidity.
        vm.stopPrank();
        vm.startPrank(celine);
        baseToken.mint(testCase.celineContribution);
        baseToken.approve(address(hyperdrive), testCase.celineContribution);
        try
            hyperdrive.addLiquidity(
                testCase.celineContribution,
                0,
                0,
                type(uint256).max,
                IHyperdrive.Options({
                    destination: celine,
                    asBase: true,
                    extraData: new bytes(0)
                })
            )
        {
            // Celine opens a large long.
            longBasePaid = longBasePaid.normalizeToRange(
                hyperdrive.getPoolConfig().minimumTransactionAmount,
                hyperdrive.calculateMaxLong().mulDown(0.9e18)
            );
            openLong(celine, longBasePaid);

            // The term advances. Alice removes her liquidity.
            advanceTime(POSITION_DURATION, int256(variableAPR));

            // Alice removes liquidity. Ensure that Alice did not lose money.
            (
                testCase.aliceBaseProceeds,
                testCase.aliceWithdrawalShares
            ) = removeLiquidity(alice, testCase.aliceLpShares);
            assertGt(testCase.aliceBaseProceeds, testCase.aliceContribution);
            assertEq(testCase.aliceWithdrawalShares, 0);
        } catch (bytes memory error) {
            assert(
                error.eq(
                    abi.encodeWithSelector(
                        IHyperdrive.CircuitBreakerTriggered.selector
                    )
                )
            );
        }
    }

    function test_sandwich_add_liquidity_long_and_short_high_time_stretch(
        uint256 aliceContribution,
        uint256 celineContribution,
        uint256 fixedAPR,
        uint256 timeStretchAPR,
        uint256 variableAPR,
        uint256 shortAmount,
        uint256 longBasePaid
    ) external {
        // Normalize most of the test parameters.
        TestCase memory testCase;
        testCase.aliceContribution = aliceContribution.normalizeToRange(
            100e18,
            100_000_000e18
        );
        testCase.celineContribution = celineContribution.normalizeToRange(
            100e18,
            100_000_000e18
        );
        timeStretchAPR = timeStretchAPR.normalizeToRange(0.05e18, 0.3e18);
        fixedAPR = fixedAPR.normalizeToRange(0.05e18, timeStretchAPR * 2);
        variableAPR = variableAPR.normalizeToRange(fixedAPR, fixedAPR * 2);

        // Execute the test.
        _test_sandwich_add_liquidity_long_and_short(
            testCase,
            fixedAPR,
            timeStretchAPR,
            variableAPR,
            shortAmount,
            longBasePaid,
            0.075e18 // circuit breaker delta = 7.5%
        );
    }

    function test_sandwich_add_liquidity_long_and_short_low_time_stretch(
        uint256 aliceContribution,
        uint256 celineContribution,
        uint256 fixedAPR,
        uint256 timeStretchAPR,
        uint256 variableAPR,
        uint256 shortAmount,
        uint256 longBasePaid
    ) external {
        // Normalize most of the test parameters.
        TestCase memory testCase;
        testCase.aliceContribution = aliceContribution.normalizeToRange(
            100e18,
            100_000_000e18
        );
        testCase.celineContribution = celineContribution.normalizeToRange(
            100e18,
            100_000_000e18
        );
        timeStretchAPR = timeStretchAPR.normalizeToRange(0.01e18, 0.05e18);
        fixedAPR = fixedAPR.normalizeToRange(0.01e18, timeStretchAPR * 2);
        variableAPR = variableAPR.normalizeToRange(fixedAPR, 0.15e18);

        // Execute the test.
        _test_sandwich_add_liquidity_long_and_short(
            testCase,
            fixedAPR,
            timeStretchAPR,
            variableAPR,
            shortAmount,
            longBasePaid,
            timeStretchAPR // circuit breaker delta = time stretch apr
        );
    }

    function _test_sandwich_add_liquidity_long_and_short(
        TestCase memory testCase,
        uint256 fixedAPR,
        uint256 timeStretchAPR,
        uint256 variableAPR,
        uint256 shortAmount,
        uint256 longBasePaid,
        uint256 circuitBreakerDelta
    ) internal {
        // Alice deploys and initializes the pool.
        IHyperdrive.PoolConfig memory config = testConfig(
            timeStretchAPR,
            POSITION_DURATION
        );
        config.fees.curve = 0.01e18;
        config.fees.flat = 0.0005e18;
        config.circuitBreakerDelta = circuitBreakerDelta;
        // NOTE: We use a low minimum share reserves to avoid issues with
        // `InvalidEffectiveShareReserves`.
        config.minimumShareReserves = 1e6;
        deploy(alice, config);
        testCase.aliceLpShares = initialize(
            alice,
            fixedAPR,
            testCase.aliceContribution
        );
        testCase.aliceContribution -=
            2 *
            hyperdrive.getPoolConfig().minimumShareReserves;

        // Celine opens a large long.
        longBasePaid = longBasePaid.normalizeToRange(
            hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxLong().mulDown(0.9e18)
        );
        openLong(celine, longBasePaid);

        // Celine adds liquidity.
        vm.stopPrank();
        vm.startPrank(celine);
        baseToken.mint(testCase.celineContribution);
        baseToken.approve(address(hyperdrive), testCase.celineContribution);
        try
            hyperdrive.addLiquidity(
                testCase.celineContribution,
                0,
                0,
                type(uint256).max,
                IHyperdrive.Options({
                    destination: celine,
                    asBase: true,
                    extraData: new bytes(0)
                })
            )
        {
            // Celine opens a large short.
            shortAmount = shortAmount.normalizeToRange(
                hyperdrive.getPoolConfig().minimumTransactionAmount,
                hyperdrive.calculateMaxShort()
            );
            openShort(celine, shortAmount);

            // The term advances and interest accrues at the original fixed rate.
            advanceTime(POSITION_DURATION, int256(variableAPR));

            // Alice removes liquidity. Ensure that Alice did not lose money.
            (
                testCase.aliceBaseProceeds,
                testCase.aliceWithdrawalShares
            ) = removeLiquidity(alice, testCase.aliceLpShares);
            assertGt(testCase.aliceBaseProceeds, testCase.aliceContribution);
            assertEq(testCase.aliceWithdrawalShares, 0);
        } catch (bytes memory error) {
            assert(
                error.eq(
                    abi.encodeWithSelector(
                        IHyperdrive.CircuitBreakerTriggered.selector
                    )
                )
            );
        }
    }
}
