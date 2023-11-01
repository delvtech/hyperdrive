// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { stdError } from "forge-std/StdError.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { MockHyperdrive } from "contracts/test/MockHyperdrive.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "test/utils/HyperdriveTest.sol";
import { Lib } from "test/utils/Lib.sol";

contract RemoveLiquidityTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    function setUp() public override {
        super.setUp();

        // Start recording event logs.
        vm.recordLogs();
    }

    /// Unit Tests ///

    function test_remove_liquidity_fail_zero_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Alice attempts to remove 0 lp shares.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(IHyperdrive.MinimumTransactionAmount.selector);
        hyperdrive.removeLiquidity(
            0,
            0,
            IHyperdrive.Options({
                destination: alice,
                asBase: false,
                extraData: new bytes(0)
            })
        );
    }

    function test_remove_liquidity_fail_insufficient_shares() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

        // Alice attempts to remove 0 lp shares.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(stdError.arithmeticError);
        hyperdrive.removeLiquidity(
            lpShares + 1,
            0,
            IHyperdrive.Options({
                destination: alice,
                asBase: false,
                extraData: new bytes(0)
            })
        );
    }

    function test_remove_liquidity_no_trades() external {
        TestCase memory testCase = TestCase({
            initializer: alice,
            fixedRate: 0.05e18,
            variableRate: 0.03e18,
            contribution: 500_000_000e18,
            timeElapsed: POSITION_DURATION.mulDown(0.05e18),
            initialLpShares: 0,
            initialLpBaseProceeds: 0,
            initialLpWithdrawalShares: 0,
            longAmount: 0,
            longBasePaid: 0,
            shortAmount: 0,
            shortBasePaid: 0
        });

        // Initialize the pool with a large amount of capital.
        testCase.initialLpShares = initialize(
            alice,
            uint256(testCase.fixedRate),
            testCase.contribution
        );
        testCase.contribution -=
            2 *
            hyperdrive.getPoolConfig().minimumShareReserves;

        // Time passes and interest accrues.
        advanceTime(testCase.timeElapsed, testCase.variableRate);

        // Remove the intializer's liquidity and verify that the state was
        // updated correctly.
        _test_remove_liquidity(testCase, false, 0);
    }

    function test_remove_liquidity_long_trade() external {
        TestCase memory testCase = TestCase({
            initializer: alice,
            fixedRate: 0.05e18,
            variableRate: 0.03e18,
            contribution: 500_000_000e18,
            timeElapsed: POSITION_DURATION.mulDown(0.05e18),
            initialLpShares: 0,
            initialLpBaseProceeds: 0,
            initialLpWithdrawalShares: 0,
            longAmount: 0,
            longBasePaid: 50_000_000e18,
            shortAmount: 0,
            shortBasePaid: 0
        });

        // Initialize the pool with a large amount of capital.
        testCase.initialLpShares = initialize(
            alice,
            uint256(testCase.fixedRate),
            testCase.contribution
        );
        testCase.contribution -=
            2 *
            hyperdrive.getPoolConfig().minimumShareReserves;

        // Time passes and interest accrues.
        advanceTime(testCase.timeElapsed, testCase.variableRate);

        // Bob opens a long.
        (, testCase.longAmount) = openLong(bob, testCase.longBasePaid);

        // Remove the intializer's liquidity and verify that the state was
        // updated correctly.
        _test_remove_liquidity(testCase, true, 2);
    }

    function test_remove_liquidity_short_trade() external {
        TestCase memory testCase = TestCase({
            initializer: alice,
            fixedRate: 0.05e18,
            variableRate: 0.03e18,
            contribution: 500_000_000e18,
            timeElapsed: POSITION_DURATION.mulDown(0.05e18),
            initialLpShares: 0,
            initialLpBaseProceeds: 0,
            initialLpWithdrawalShares: 0,
            longAmount: 0,
            longBasePaid: 0,
            shortAmount: 50_000_000e18,
            shortBasePaid: 0
        });

        // Initialize the pool with a large amount of capital.
        testCase.initialLpShares = initialize(
            alice,
            uint256(testCase.fixedRate),
            testCase.contribution
        );
        testCase.contribution -=
            2 *
            hyperdrive.getPoolConfig().minimumShareReserves;

        // Time passes and interest accrues.
        advanceTime(testCase.timeElapsed, testCase.variableRate);

        // Bob opens a short.
        (, testCase.shortBasePaid) = openShort(bob, testCase.shortAmount);

        // Remove the intializer's liquidity and verify that the state was
        // updated correctly.
        _test_remove_liquidity(testCase, false, 3e7); // TODO: Reduce this bound.
    }

    /// Helpers ///

    struct TestCase {
        address initializer;
        int256 fixedRate;
        int256 variableRate;
        uint256 contribution;
        uint256 timeElapsed;
        uint256 initialLpShares;
        uint256 initialLpBaseProceeds;
        uint256 initialLpWithdrawalShares;
        uint256 longAmount;
        uint256 longBasePaid;
        uint256 shortAmount;
        uint256 shortBasePaid;
    }

    /// @dev This test assumes that the Hyperdrive pool has been initialized and
    ///      that the pool's liquidity providers haven't changed since
    ///      initialization. The initializer removes all of their liquidity, and
    ///      we ensure that they receive the correct amount of base and
    ///      withdrawal shares.
    /// @param testCase The test case.
    /// @param isLong True if the trade that was opened is a long and false
    ///        otherwise. The current netting implementation is overly
    ///        conservative, which results in double counting the margin that
    ///        LPs must reserve for LPs. This double counting isn't done in the
    ///        case of shorts.
    /// @param tolerance The error tolerance for imprecise assertions.
    function _test_remove_liquidity(
        TestCase memory testCase,
        bool isLong,
        uint256 tolerance
    ) internal {
        // The LPs provided margins for all of the open trades. We can calculate
        // this margin starting with the idle calculation:
        // idle = z * c - l_e - z_min
        //
        // when a long is opened idle changes by:
        // idle = (z + dz) * c - (l_e + dy) - z_min
        // delta idle = dz * c - dy
        // new idle = old idle + delta idle (since dy > dz*c idle goes down)
        //
        // When a short is opened the share reserves decrease and so does the exposure:
        // idle = (z*c - (dy - dz*c)) - l_e - z_min
        // delta idle = dy - dz *c =  - dz * c + dy
        // new idle = old idle + delta idle (since dy > dz*c idle goes up)
        uint256 marginFactor = 1;
        if (isLong) {
            marginFactor = 2;
        }
        uint256 margin = (testCase.longAmount - testCase.longBasePaid) +
            (testCase.shortAmount - testCase.shortBasePaid);
        uint256 remainingMargin = uint256(marginFactor * margin).mulDivDown(
            hyperdrive.getPoolConfig().minimumShareReserves,
            testCase.initialLpShares +
                hyperdrive.getPoolConfig().minimumShareReserves
        );

        // Read from the state before removing liquidity.
        uint256 fixedRateBefore = hyperdrive.calculateSpotAPR();
        uint256 lpTotalSupplyBefore = lpTotalSupply();
        uint256 startingPresentValue = hyperdrive.presentValue();
        uint256 expectedBaseProceeds = calculateBaseLpProceeds(
            testCase.initialLpShares
        );

        // The pool's initializer removes all of their liquidity. Ensure that
        // they get the expected amount of base and withdrawal shares. They
        // should receive their initial contribution plus the interest that
        // accrues minus the amount of margin they provided for the short
        // position.
        (
            testCase.initialLpBaseProceeds,
            testCase.initialLpWithdrawalShares
        ) = removeLiquidity(testCase.initializer, testCase.initialLpShares);
        assertEq(testCase.initialLpBaseProceeds, expectedBaseProceeds);
        (uint256 contributionPlusInterest, ) = HyperdriveUtils
            .calculateCompoundInterest(
                testCase.contribution,
                testCase.variableRate,
                testCase.timeElapsed
            );
        {
            uint256 initializerMargin = uint256(margin).mulDivDown(
                testCase.initialLpShares,
                testCase.initialLpShares +
                    hyperdrive.getPoolConfig().minimumShareReserves
            );
            assertApproxEqAbs(
                expectedBaseProceeds,
                contributionPlusInterest - marginFactor * initializerMargin,
                tolerance
            );
            assertEq(
                baseToken.balanceOf(alice),
                testCase.initialLpBaseProceeds
            );
            uint256 expectedWithdrawalShares = calculateWithdrawalShares(
                testCase.initialLpShares,
                startingPresentValue,
                HyperdriveUtils.presentValue(hyperdrive),
                lpTotalSupplyBefore
            );
            assertApproxEqAbs(
                testCase.initialLpWithdrawalShares,
                expectedWithdrawalShares,
                1
            );

            // Ensure that the correct event was emitted.
            verifyRemoveLiquidityEvent(
                testCase.initialLpShares,
                testCase.initialLpBaseProceeds,
                testCase.initialLpWithdrawalShares
            );

            // Ensure that the fixed rate stayed the same after removing liquidity.
            assertEq(hyperdrive.calculateSpotAPR(), fixedRateBefore);

            // Ensure that the initializer's shares were burned and that the total
            // LP supply is just the minimum share reserves.
            assertEq(hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice), 0);
            assertEq(
                hyperdrive.totalSupply(AssetId._LP_ASSET_ID),
                hyperdrive.getPoolConfig().minimumShareReserves
            );

            // Ensure that the initializer receives the right amount of withdrawal
            // shares.
            assertApproxEqAbs(
                hyperdrive.balanceOf(AssetId._WITHDRAWAL_SHARE_ASSET_ID, alice),
                expectedWithdrawalShares,
                1
            );
        }
        // Ensure that the pool still has the correct amount of base and shares.
        // The pool should have the full bond amount reserved to pay out the
        // bonds at maturity. Additionally, the pool should have the minimum
        // share reserves and the zero address's initial contribution (also
        // equal to the minimum share reserves) minus the amount of margin the
        // zero address provided for the short. The bond amount isn't included
        // in the share reserves, so the share reserves should be equal to the
        // minimum share reserves plus the zero address's unused idle capital.
        //
        // Since margin is double counted in the case of long trades, we add
        // an extra margin term in the expected base balance and share reserves
        // in the case of long trades.
        uint256 reservedShares = 2 *
            hyperdrive.getPoolConfig().minimumShareReserves -
            remainingMargin.divDown(hyperdrive.getPoolInfo().sharePrice);
        uint256 expectedBaseBalance = testCase.longAmount +
            testCase.shortAmount +
            margin *
            (marginFactor - 1) +
            reservedShares.mulDown(hyperdrive.getPoolInfo().sharePrice);
        uint256 expectedShareReserves = reservedShares +
            (margin * (marginFactor - 1) + testCase.longAmount).divDown(
                hyperdrive.getPoolInfo().sharePrice
            );
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            expectedBaseBalance,
            tolerance
        );
        assertApproxEqAbs(
            hyperdrive.getPoolInfo().shareReserves,
            expectedShareReserves,
            1
        );
    }

    function verifyRemoveLiquidityEvent(
        uint256 expectedLpShares,
        uint256 expectedBaseAmount,
        uint256 expectedWithdrawalShares
    ) internal {
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            RemoveLiquidity.selector
        );
        assertEq(logs.length, 1);
        VmSafe.Log memory log = logs[0];
        assertEq(address(uint160(uint256(log.topics[1]))), alice);
        (uint256 lpShares, uint256 baseAmount, uint256 withdrawalShares) = abi
            .decode(log.data, (uint256, uint256, uint256));
        assertEq(lpShares, expectedLpShares);
        assertEq(baseAmount, expectedBaseAmount);
        assertEq(withdrawalShares, expectedWithdrawalShares);
    }

    function lpTotalSupply() internal view returns (uint256) {
        return
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID) +
            hyperdrive.totalSupply(AssetId._WITHDRAWAL_SHARE_ASSET_ID) -
            hyperdrive.getPoolInfo().withdrawalSharesReadyToWithdraw;
    }

    function presentValueRatio() internal view returns (uint256) {
        return
            hyperdrive.presentValue().divDown(
                lpTotalSupply().mulDown(hyperdrive.getPoolInfo().sharePrice)
            );
    }

    function calculateWithdrawalShares(
        uint256 _shares,
        uint256 _startingPresentValue,
        uint256 _endingPresentValue,
        uint256 _lpTotalSupplyBefore
    ) internal pure returns (uint256) {
        uint256 withdrawalShares = _endingPresentValue.mulDown(
            _lpTotalSupplyBefore
        );
        withdrawalShares += _startingPresentValue.mulDown(_shares);
        withdrawalShares -= _startingPresentValue.mulDown(_lpTotalSupplyBefore);
        withdrawalShares = withdrawalShares.divDown(_startingPresentValue);
        return withdrawalShares;
    }
}
