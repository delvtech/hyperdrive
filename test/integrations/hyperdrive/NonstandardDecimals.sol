// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockHyperdrive } from "../../mocks/MockHyperdrive.sol";
import { Lib } from "../../utils/Lib.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";

contract NonstandardDecimalsTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;

    function test_nonstandard_decimals_initialize(
        uint256 apr,
        uint256 contribution
    ) external {
        // Normalize the fuzzed variables.
        apr = apr.normalizeToRange(0.001e18, 2e18);
        contribution = contribution.normalizeToRange(1e6, 1_000_000_000e6);

        // Initialize the pool and ensure that the APR is correct.
        initialize(alice, apr, contribution);
        assertApproxEqAbs(
            HyperdriveUtils.calculateAPRFromReserves(hyperdrive),
            apr,
            1e12
        );
    }

    function test_nonstandard_decimals_long(
        uint256 basePaid,
        uint256 holdTime,
        int256 variableRate
    ) external {
        // Normalize the fuzzed variables.
        initialize(alice, 0.02e18, 500_000_000e6);
        basePaid = basePaid.normalizeToRange(
            0.001e6,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        holdTime = holdTime.normalizeToRange(0, POSITION_DURATION);
        variableRate = variableRate.normalizeToRange(0, 2e18);

        // Bob opens a long and closes immediately. He should receive
        // essentially all of his capital back.
        {
            // Deploy and initialize the pool.
            deploy(alice, 0.02e18, 0, 0, 0);
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
            deploy(alice, 0.02e18, 0, 0, 0);
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
            deploy(alice, 0.02e18, 0, 0, 0);
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
        shortAmount = shortAmount.normalizeToRange(
            0.01e6,
            HyperdriveUtils.calculateMaxShort(hyperdrive).mulDown(0.9e18)
        );
        holdTime = holdTime.normalizeToRange(0, POSITION_DURATION);
        variableRate = variableRate.normalizeToRange(0, 2e18);

        // Bob opens a short and closes immediately. He should receive
        // essentially all of his capital back.
        {
            // Deploy and initialize the pool.
            deploy(alice, 0.02e18, 0, 0, 0);
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
        // snapshotId = vm.snapshot();
        {
            // Deploy and initialize the pool.
            deploy(alice, 0.02e18, 0, 0, 0);
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
            deploy(alice, 0.02e18, 0, 0, 0);
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
        ///    longBasePaid = 279154570667275;

        // Set up the test parameters.
        TestLpWithdrawalParams memory testParams = TestLpWithdrawalParams({
            fixedRate: 0.02e18,
            variableRate: 0,
            contribution: 550_000_000e6,
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
        longBasePaid = longBasePaid.normalizeToRange(
            0.01e6,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        testParams.longBasePaid = longBasePaid;
        {
            (uint256 longMaturityTime, uint256 longAmount) = openLong(
                bob,
                testParams.longBasePaid
            );
            testParams.longMaturityTime = longMaturityTime;
            testParams.longAmount = longAmount;
        }

        // Bob opens a short.
        shortAmount = shortAmount.normalizeToRange(
            1e6, // TODO: We should be able to use a lower tolerance like 0.1e6.
            HyperdriveUtils.calculateMaxShort(hyperdrive)
        );
        testParams.shortAmount = shortAmount;
        {
            (uint256 shortMaturityTime, uint256 shortBasePaid) = openShort(
                bob,
                testParams.shortAmount
            );
            testParams.shortMaturityTime = shortMaturityTime;
            testParams.shortBasePaid = shortBasePaid;
        }

        // Alice removes her liquidity.
        (
            uint256 aliceBaseProceeds,
            uint256 aliceWithdrawalShares
        ) = removeLiquidity(alice, aliceLpShares);
        uint256 aliceMargin = ((testParams.longAmount -
            testParams.longBasePaid) +
            (testParams.shortAmount - testParams.shortBasePaid)) / 2;
        assertApproxEqAbs(
            aliceBaseProceeds,
            testParams.contribution - aliceMargin,
            10
        );

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

        // Redeem Alice's withdrawal shares. Alice at least the margin released
        // from Bob's long.
        (uint256 aliceRedeemProceeds, ) = redeemWithdrawalShares(
            alice,
            aliceWithdrawalShares
        );
        assertGe(aliceRedeemProceeds + 1e2, aliceMargin);

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
        assertGe(bobBaseProceeds + 1e2, celineBaseProceeds);
        assertGe(bobBaseProceeds + 1e2, testParams.contribution);
        assertApproxEqAbs(bobWithdrawalShares, 0, 1);
        assertApproxEqAbs(celineWithdrawalShares, 0, 1);

        // Ensure that the ending base balance of Hyperdrive is zero.
        assertApproxEqAbs(
            hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID) -
                hyperdrive.getPoolInfo().withdrawalSharesReadyToWithdraw,
            0,
            1
        );
        // TODO: There is an edge case where the withdrawal pool doesn't receive
        // all of its portion of the available idle liquidity when a closed
        // position doesn't perform well.
        // assertApproxEqAbs(baseToken.balanceOf(address(hyperdrive)), 0, 1);
    }
}
