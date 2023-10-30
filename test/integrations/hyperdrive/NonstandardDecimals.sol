// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockHyperdrive } from "../../mocks/MockHyperdrive.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract NonstandardDecimalsTest is HyperdriveTest {
    using FixedPointMath for int256;
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    function setUp() public override {
        super.setUp();

        // Deploy the pool with a small minimum share reserves since we're
        // using nonstandard decimals in this suite.
        IHyperdrive.PoolConfig memory config = testConfig(0.05e18);
        config.minimumShareReserves = 1e6;
        config.minimumTransactionAmount = 1e6;
        deploy(deployer, config);
    }

    function test_nonstandard_decimals_longs_outstanding() external {
        // Deploy and initialize the pool.
        IHyperdrive.PoolConfig memory config = testConfig(0.02e18);
        config.minimumShareReserves = 1e6;
        config.minimumTransactionAmount = 1e6;
        deploy(deployer, config);
        initialize(alice, 0.02e18, 500_000_000e6);

        // Bob opens a long.
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, 1e6);

        // Check that the longs outstanding increased by the correct amount.
        assertEq(hyperdrive.getPoolInfo().longsOutstanding, longAmount);

        // The term passes.
        advanceTime(POSITION_DURATION, 0.05e18);
        uint256 longsOustandingBefore = hyperdrive
            .getPoolInfo()
            .longsOutstanding;

        // Bob closes the long.
        closeLong(bob, maturityTime, longAmount);

        // Check that the longs outstanding decreased by the correct amount.
        assertEq(
            hyperdrive.getPoolInfo().longsOutstanding,
            longsOustandingBefore - longAmount
        );
    }

    function test_nonstandard_decimals_shorts_outstanding() external {
        // Deploy and initialize the pool.
        IHyperdrive.PoolConfig memory config = testConfig(0.02e18);
        config.minimumShareReserves = 1e6;
        config.minimumTransactionAmount = 1e6;
        deploy(deployer, config);
        initialize(alice, 0.02e18, 500_000_000e6);

        // Bob opens a short.
        uint256 shortAmount = 1e6;
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // Check that the shorts outstanding increased by the correct amount.
        assertEq(hyperdrive.getPoolInfo().shortsOutstanding, shortAmount);

        // The term passes.
        advanceTime(POSITION_DURATION, 0.05e18);
        uint256 shortsOustandingBefore = hyperdrive
            .getPoolInfo()
            .shortsOutstanding;

        // Bob closes the short.
        closeShort(bob, maturityTime, shortAmount);

        // Check that the shorts outstanding decreased by the correct amount.
        assertEq(
            hyperdrive.getPoolInfo().longsOutstanding,
            shortsOustandingBefore - shortAmount
        );
    }

    function test_nonstandard_decimals_initialize(
        uint256 apr,
        uint256 contribution
    ) external {
        // Normalize the fuzzed variables.
        apr = apr.normalizeToRange(0.001e18, 2e18);
        contribution = contribution.normalizeToRange(2e6, 1_000_000_000e6);

        // Initialize the pool and ensure that the APR is correct.
        initialize(alice, apr, contribution);
        assertApproxEqAbs(hyperdrive.calculateSpotAPR(), apr, 1e12);
    }

    function test_nonstandard_decimals_long(
        uint256 basePaid,
        uint256 holdTime,
        int256 variableRate
    ) external {
        // Normalize the fuzzed variables.
        initialize(alice, 0.02e18, 500_000_000e6);
        uint256 maxLong = HyperdriveUtils.calculateMaxLong(hyperdrive);
        basePaid = basePaid.normalizeToRange(
            hyperdrive.getPoolConfig().minimumTransactionAmount,
            maxLong
        );
        holdTime = holdTime.normalizeToRange(0, POSITION_DURATION);
        variableRate = variableRate.normalizeToRange(0, 2e18);

        // Bob opens a long and closes immediately. He should receive
        // essentially all of his capital back.
        {
            // Deploy and initialize the pool.
            IHyperdrive.PoolConfig memory config = testConfig(0.02e18);
            config.minimumShareReserves = 1e6;
            config.minimumTransactionAmount = 1e6;
            deploy(deployer, config);
            initialize(alice, 0.02e18, 500_000_000e6);

            // Bob opens a long.
            (uint256 maturityTime, uint256 longAmount) = openLong(
                bob,
                basePaid
            );

            // Bob closes the long.
            uint256 baseProceeds = closeLong(bob, maturityTime, longAmount);
            assertApproxEqAbs(basePaid, baseProceeds, 1e2);
        }

        // Bob opens a long and holds for a random time less than the position
        // duration. He should receive the base he paid plus fixed interest.
        {
            // Deploy and initialize the pool.
            IHyperdrive.PoolConfig memory config = testConfig(0.02e18);
            config.minimumShareReserves = 1e6;
            config.minimumTransactionAmount = 1e6;
            deploy(deployer, config);
            initialize(alice, 0.02e18, 500_000_000e6);

            // Bob opens a long.
            (uint256 maturityTime, uint256 longAmount) = openLong(
                bob,
                basePaid
            );
            uint256 fixedRate = HyperdriveUtils.calculateAPRFromRealizedPrice(
                basePaid,
                longAmount,
                HyperdriveUtils.calculateTimeRemaining(hyperdrive, maturityTime)
            );

            // The term passes.
            advanceTime(holdTime, variableRate);

            // Bob closes the long.
            (uint256 expectedBaseProceeds, ) = HyperdriveUtils
                .calculateInterest(basePaid, int256(fixedRate), holdTime);
            uint256 baseProceeds = closeLong(bob, maturityTime, longAmount);
            uint256 range = baseProceeds > 1e6
                ? baseProceeds.mulDown(0.01e18)
                : 1e3; // TODO: This is a large bound. Investigate this further
            assertApproxEqAbs(baseProceeds, expectedBaseProceeds, range);
        }

        // Bob opens a long and holds to maturity. He should receive the face
        // value of the bonds.
        {
            // Deploy and initialize the pool.
            IHyperdrive.PoolConfig memory config = testConfig(0.02e18);
            config.minimumShareReserves = 1e6;
            config.minimumTransactionAmount = 1e6;
            deploy(deployer, config);
            initialize(alice, 0.02e18, 500_000_000e6);

            // Bob opens a long.
            (uint256 maturityTime, uint256 longAmount) = openLong(
                bob,
                basePaid
            );

            // The term passes.
            advanceTime(POSITION_DURATION, variableRate);

            // Bob closes the long.
            uint256 baseProceeds = closeLong(bob, maturityTime, longAmount);
            assertApproxEqAbs(baseProceeds, longAmount, 1e2);
        }
    }

    function test_nonstandard_decimals_short(
        uint256 shortAmount,
        uint256 holdTime,
        int256 variableRate
    ) external {
        // Normalize the fuzzed variables.
        initialize(alice, 0.02e18, 500_000_000e6);
        uint256 maxShort = HyperdriveUtils
            .calculateMaxShort(hyperdrive)
            .mulDown(0.9e18);
        shortAmount = shortAmount.normalizeToRange(
            hyperdrive.getPoolConfig().minimumTransactionAmount,
            maxShort
        );
        holdTime = holdTime.normalizeToRange(0, POSITION_DURATION);
        variableRate = variableRate.normalizeToRange(0, 2e18);

        // Bob opens a short and closes immediately. He should receive
        // essentially all of his capital back.
        {
            // Deploy and initialize the pool.
            IHyperdrive.PoolConfig memory config = testConfig(0.02e18);
            config.minimumShareReserves = 1e6;
            config.minimumTransactionAmount = 1e6;
            deploy(deployer, config);
            initialize(alice, 0.02e18, 500_000_000e6);

            // Bob opens a short.
            (uint256 maturityTime, uint256 basePaid) = openShort(
                bob,
                shortAmount
            );

            // Bob closes the long.
            uint256 baseProceeds = closeShort(bob, maturityTime, shortAmount);
            assertApproxEqAbs(basePaid, baseProceeds, 1e2);
        }

        // Bob opens a short and holds for a random time less than the position
        // duration. He should receive the base he paid plus the variable
        // interest minus the fixed interest.
        {
            // Deploy and initialize the pool.
            IHyperdrive.PoolConfig memory config = testConfig(0.02e18);
            config.minimumShareReserves = 1e6;
            config.minimumTransactionAmount = 1e6;
            deploy(deployer, config);
            initialize(alice, 0.02e18, 500_000_000e6);

            // Bob opens a short.
            (uint256 maturityTime, uint256 basePaid) = openShort(
                bob,
                shortAmount
            );
            uint256 lpBasePaid = shortAmount - basePaid;
            uint256 fixedRate = HyperdriveUtils.calculateAPRFromRealizedPrice(
                lpBasePaid,
                shortAmount,
                HyperdriveUtils.calculateTimeRemaining(hyperdrive, maturityTime)
            );

            // The term passes.
            advanceTime(holdTime, variableRate);

            // Bob closes the short.
            (, int256 fixedInterest) = HyperdriveUtils.calculateInterest(
                lpBasePaid,
                int256(fixedRate),
                holdTime
            );
            (, int256 variableInterest) = HyperdriveUtils
                .calculateCompoundInterest(shortAmount, variableRate, holdTime);
            uint256 expectedBaseProceeds = basePaid +
                uint256(variableInterest) -
                uint256(fixedInterest);
            uint256 baseProceeds = closeShort(bob, maturityTime, shortAmount);
            assertApproxEqAbs(baseProceeds, expectedBaseProceeds, 1e13);
        }

        // Bob opens a short and holds to maturity. He should receive the
        // variable interest earned by the short.
        {
            // Deploy and initialize the pool.
            IHyperdrive.PoolConfig memory config = testConfig(0.02e18);
            config.minimumShareReserves = 1e6;
            config.minimumTransactionAmount = 1e6;
            deploy(deployer, config);
            initialize(alice, 0.02e18, 500_000_000e6);

            // Bob opens a short.
            (uint256 maturityTime, ) = openShort(bob, shortAmount);

            // The term passes.
            advanceTime(POSITION_DURATION, variableRate);

            // Bob closes the short.
            (, int256 variableInterest) = HyperdriveUtils
                .calculateCompoundInterest(
                    shortAmount,
                    variableRate,
                    POSITION_DURATION
                );
            uint256 baseProceeds = closeShort(bob, maturityTime, shortAmount);
            assertApproxEqAbs(baseProceeds, uint256(variableInterest), 1e2);
        }
    }

    struct TestLpWithdrawalParams {
        int256 fixedRate;
        int256 variableRate;
        uint256 contribution;
        uint256 longAmount;
        uint256 longBasePaid;
        uint256 longMaturityTime;
        uint256 shortAmount;
        uint256 shortBasePaid;
        uint256 shortMaturityTime;
    }

    function test_nonstandard_decimals_lp(
        uint256 longBasePaid,
        uint256 shortAmount
    ) external {
        _test_nonstandard_decimals_lp(longBasePaid, shortAmount);
    }

    function test_nonstandard_decimals_lp_edge_cases() external {
        {
            uint256 longBasePaid = 2141061247565828640207640148726033314;
            uint256 shortAmount = 0;
            _test_nonstandard_decimals_lp(longBasePaid, shortAmount);
        }
        {
            uint256 longBasePaid = 1; // 0.001001
            uint256 shortAmount = 148459608630430972478345391529005226647846873482005235753473233;
            _test_nonstandard_decimals_lp(longBasePaid, shortAmount);
        }
        {
            uint256 longBasePaid = 24392;
            uint256 shortAmount = 5578;
            _test_nonstandard_decimals_lp(longBasePaid, shortAmount);
        }
        {
            uint256 longBasePaid = 27201;
            uint256 shortAmount = 51735872838114005798240350212166451602148334066294109046196838703383171970103;
            _test_nonstandard_decimals_lp(longBasePaid, shortAmount);
        }
        {
            uint256 longBasePaid = 17953;
            uint256 shortAmount = 4726;
            _test_nonstandard_decimals_lp(longBasePaid, shortAmount);
        }
    }

    // TODO: This test should be re-written to avoid such large tolerances.
    function _test_nonstandard_decimals_lp(
        uint256 longBasePaid,
        uint256 shortAmount
    ) internal {
        // Redeploy the pool so that the edge cases function can call it repeatedly.
        IHyperdrive.PoolConfig memory config = testConfig(0.05e18);
        config.minimumShareReserves = 1e6;
        config.minimumTransactionAmount = 1e6;
        deploy(deployer, config);

        uint256 minimumTransactionAmount = hyperdrive
            .getPoolConfig()
            .minimumTransactionAmount;

        // Set up the test parameters.
        TestLpWithdrawalParams memory testParams = TestLpWithdrawalParams({
            fixedRate: 0.02e18,
            variableRate: 0,
            contribution: 500_000_000e6,
            longAmount: 0,
            longBasePaid: 0,
            longMaturityTime: 0,
            shortAmount: 0,
            shortBasePaid: 0,
            shortMaturityTime: 0
        });

        // Initialize the pool.
        uint256 aliceLpShares = initialize(
            alice,
            uint256(testParams.fixedRate),
            testParams.contribution
        );

        // Bob adds liquidity.
        uint256 bobLpShares = addLiquidity(bob, testParams.contribution);

        // Bob opens a long.
        {
            uint256 maxLong = HyperdriveUtils.calculateMaxLong(hyperdrive);
            longBasePaid = longBasePaid.normalizeToRange(
                minimumTransactionAmount,
                maxLong - minimumTransactionAmount
            );

            testParams.longBasePaid = longBasePaid;
            (uint256 longMaturityTime, uint256 longAmount) = openLong(
                bob,
                testParams.longBasePaid
            );
            testParams.longMaturityTime = longMaturityTime;
            testParams.longAmount = longAmount;
        }

        // Bob opens a short.
        {
            uint256 maxShort = HyperdriveUtils.calculateMaxShort(hyperdrive);
            shortAmount = shortAmount.normalizeToRange(
                minimumTransactionAmount,
                maxShort - minimumTransactionAmount
            );
            testParams.shortAmount = shortAmount;
            (uint256 shortMaturityTime, uint256 shortBasePaid) = openShort(
                bob,
                testParams.shortAmount
            );
            testParams.shortMaturityTime = shortMaturityTime;
            testParams.shortBasePaid = shortBasePaid;
        }

        // Alice removes her liquidity.
        uint256 estimatedBaseProceeds = calculateBaseLpProceeds(aliceLpShares);
        (
            uint256 aliceBaseProceeds,
            uint256 aliceWithdrawalShares
        ) = removeLiquidity(alice, aliceLpShares);
        uint256 lpMargin = uint256(
            (int256(testParams.longAmount - testParams.longBasePaid) -
                int256(testParams.shortBasePaid)).max(0)
        );
        assertEq(aliceBaseProceeds, estimatedBaseProceeds);

        // Celine adds liquidity.
        uint256 celineLpShares = addLiquidity(celine, testParams.contribution);

        // Bob closes his long and his short.
        {
            closeLong(bob, testParams.longMaturityTime, testParams.longAmount);
            closeShort(
                bob,
                testParams.shortMaturityTime,
                testParams.shortAmount
            );
        }

        // Redeem Alice's withdrawal shares. Alice gets at least the margin released
        // from Bob's long.
        (uint256 aliceRedeemProceeds, ) = redeemWithdrawalShares(
            alice,
            aliceWithdrawalShares
        );
        {
            uint256 estimatedRedeemProceeds = lpMargin.mulDivDown(
                aliceLpShares,
                aliceLpShares + bobLpShares
            );
            assertGe(aliceRedeemProceeds, estimatedRedeemProceeds);
        }

        // Bob and Celine remove their liquidity. Bob should receive more base
        // proceeds than Celine since Celine's add liquidity resulted in an
        // increase in slippage for the outstanding positions.
        (
            uint256 bobBaseProceeds,
            uint256 bobWithdrawalShares
        ) = removeLiquidity(bob, bobLpShares);
        (
            uint256 celineBaseProceeds,
            uint256 celineWithdrawalShares
        ) = removeLiquidity(celine, celineLpShares);
        assertGe(bobBaseProceeds + 1e6, celineBaseProceeds);
        assertGe(bobBaseProceeds + 1e6, testParams.contribution);
        assertApproxEqAbs(bobWithdrawalShares, 0, 1);
        assertApproxEqAbs(celineWithdrawalShares, 0, 1);
        assertApproxEqAbs(
            hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID) -
                hyperdrive.getPoolInfo().withdrawalSharesReadyToWithdraw,
            0,
            1 wei
        );

        // TODO: There is an edge case where the withdrawal pool doesn't receive
        // all of its portion of the available idle liquidity when a closed
        // position doesn't perform well.
        // Ensure that the ending base balance of Hyperdrive is zero.
        // assertApproxEqAbs(baseToken.balanceOf(address(hyperdrive)), 0, 1);
    }
}
