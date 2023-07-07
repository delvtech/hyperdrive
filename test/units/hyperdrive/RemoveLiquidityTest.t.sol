// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

// FIXME
import "forge-std/console.sol";

import { stdError } from "forge-std/StdError.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract RemoveLiquidityTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    function setUp() public override {
        super.setUp();

        // Start recording event logs.
        vm.recordLogs();
    }

    function test_remove_liquidity_fail_zero_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Alice attempts to remove 0 lp shares.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(IHyperdrive.ZeroAmount.selector);
        hyperdrive.removeLiquidity(0, 0, alice, false);
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
        hyperdrive.removeLiquidity(lpShares + 1, 0, alice, false);
    }

    function test_remove_liquidity_no_trades() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);
        contribution -= 2 * hyperdrive.getPoolConfig().minimumShareReserves;

        // Time passes and interest accrues.
        uint256 timeAdvanced = POSITION_DURATION.mulDown(0.05e18);
        advanceTime(timeAdvanced, int256(apr));

        // Alice removes all of her liquidity.
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            alice,
            lpShares
        );
        verifyRemoveLiquidityEvent(lpShares, baseProceeds, withdrawalShares);

        // Ensure that the LP shares were properly accounted for.
        assertEq(hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice), 0);
        assertEq(
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID),
            hyperdrive.getPoolConfig().minimumShareReserves
        );

        // Calculate how much interest has accrued on the initial contribution
        (uint256 contributionPlusInterest, ) = HyperdriveUtils
            .calculateCompoundInterest(contribution, int256(apr), timeAdvanced);

        // Ensure that Alice received the correct amount of base.
        assertEq(baseProceeds, contributionPlusInterest);
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            2 *
                hyperdrive.getPoolConfig().minimumShareReserves.mulDown(
                    hyperdrive.getPoolInfo().sharePrice
                )
        );
        assertEq(baseToken.balanceOf(alice), baseProceeds);

        // Ensure that the reserves were updated correctly.
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        assertEq(
            poolInfo.shareReserves,
            2 * hyperdrive.getPoolConfig().minimumShareReserves
        );
        assertApproxEqAbs(hyperdrive.calculateAPRFromReserves(), apr, 1);

        // Ensure that Alice receives the right amount of withdrawal shares.
        assertEq(
            hyperdrive.balanceOf(AssetId._WITHDRAWAL_SHARE_ASSET_ID, alice),
            0
        );
    }

    function test_remove_liquidity_long_trade() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        console.log(1);
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);
        contribution -= 2 * hyperdrive.getPoolConfig().minimumShareReserves;
        console.log(2);

        // Time passes and interest accrues.
        uint256 timeAdvanced = POSITION_DURATION.mulDown(0.5e18);
        advanceTime(timeAdvanced, int256(apr));
        console.log(3);

        // Bob opens a long.
        uint256 baseAmount = 50_000_000e18;
        (, uint256 bondAmount) = openLong(bob, baseAmount);
        uint256 poolApr = HyperdriveUtils.calculateAPRFromReserves(hyperdrive);
        console.log(4);

        // Alice removes all of her liquidity.
        uint256 lpTotalSupplyBefore = lpTotalSupply();
        uint256 startingPresentValue = HyperdriveUtils.presentValue(hyperdrive);
        uint256 expectedBaseProceeds = calculateBaseProceeds(lpShares);
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            alice,
            lpShares
        );
        uint256 expectedWithdrawalShares = calculateWithdrawalShares(
            lpShares,
            startingPresentValue,
            HyperdriveUtils.presentValue(hyperdrive),
            lpTotalSupplyBefore
        );
        assertApproxEqAbs(withdrawalShares, expectedWithdrawalShares, 1);
        console.log(5);

        // Ensure that the correct event was emitted.
        verifyRemoveLiquidityEvent(lpShares, baseProceeds, withdrawalShares);
        console.log(6);

        // Ensure that the LP shares were properly accounted for.
        assertEq(hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice), 0);
        assertEq(
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID),
            hyperdrive.getPoolConfig().minimumShareReserves
        );
        console.log(7);

        // Ensure that Alice received the correct amount of base and that
        // Hyperdrive's base balance is equal to the sum of the bond amount, the
        // minimum share reserves, and the present value of the zero address's
        // LP present value.
        (uint256 contributionPlusInterest, ) = HyperdriveUtils
            .calculateCompoundInterest(contribution, int256(apr), timeAdvanced);
        console.log("7.1");
        assertApproxEqAbs(
            expectedBaseProceeds,
            contributionPlusInterest - (bondAmount - baseAmount),
            1
        );
        console.log("7.2");
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            bondAmount +
                hyperdrive.getPoolConfig().minimumShareReserves.mulDown(
                    hyperdrive.getPoolInfo().sharePrice
                ),
            1
        );
        console.log("7.3");
        assertApproxEqAbs(baseToken.balanceOf(alice), baseProceeds, 1);
        console.log(8);

        // Ensure that the reserves were updated correctly.
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        assertEq(
            poolInfo.shareReserves,
            bondAmount.divDown(hyperdrive.getPoolInfo().sharePrice) +
                hyperdrive.getPoolConfig().minimumShareReserves
        );
        assertApproxEqAbs(
            HyperdriveUtils.calculateAPRFromReserves(hyperdrive),
            poolApr,
            1
        );
        console.log(9);

        // Ensure that Alice receives the right amount of withdrawal shares.
        assertApproxEqAbs(
            hyperdrive.balanceOf(AssetId._WITHDRAWAL_SHARE_ASSET_ID, alice),
            expectedWithdrawalShares,
            1
        );
        console.log(10);
    }

    function test_remove_liquidity_short_trade() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        console.log("test_remove_liquidity_short_trade: 1");
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);
        contribution -= 2 * hyperdrive.getPoolConfig().minimumShareReserves;
        console.log("test_remove_liquidity_short_trade: 2");

        // Time passes and interest accrues.
        uint256 timeAdvanced = POSITION_DURATION.mulDown(0.05e18);
        advanceTime(timeAdvanced, int256(apr));
        console.log("test_remove_liquidity_short_trade: 3");

        // Bob opens a short.
        uint256 bondAmount = 50_000_000e18;
        (, uint256 basePaid) = openShort(bob, bondAmount);
        uint256 aprAfterTrade = hyperdrive.calculateAPRFromReserves();
        console.log("test_remove_liquidity_short_trade: 4");

        // Alice removes all of her liquidity.
        uint256 lpTotalSupplyBefore = lpTotalSupply();
        uint256 startingPresentValue = HyperdriveUtils.presentValue(hyperdrive);
        uint256 expectedBaseProceeds = calculateBaseProceeds(lpShares);
        (uint256 baseProceeds, uint256 withdrawalShares) = removeLiquidity(
            alice,
            lpShares
        );
        uint256 expectedWithdrawalShares = calculateWithdrawalShares(
            lpShares,
            startingPresentValue,
            HyperdriveUtils.presentValue(hyperdrive),
            lpTotalSupplyBefore
        );
        assertEq(baseProceeds, expectedBaseProceeds);
        assertApproxEqAbs(withdrawalShares, expectedWithdrawalShares, 1);
        console.log("test_remove_liquidity_short_trade: 5");

        // Ensure that the correct event was emitted.
        verifyRemoveLiquidityEvent(lpShares, baseProceeds, withdrawalShares);
        console.log("test_remove_liquidity_short_trade: 5");

        // Ensure that the LP shares were properly accounted for.
        assertEq(hyperdrive.balanceOf(AssetId._LP_ASSET_ID, alice), 0);
        assertEq(
            hyperdrive.totalSupply(AssetId._LP_ASSET_ID),
            hyperdrive.getPoolConfig().minimumShareReserves
        );
        console.log("test_remove_liquidity_short_trade: 6");

        // Ensure that Alice received the correct amount of base.
        (uint256 contributionPlusInterest, ) = HyperdriveUtils
            .calculateCompoundInterest(contribution, int256(apr), timeAdvanced);
        // TODO: Improve this bound.
        console.log("6.1");
        assertApproxEqAbs(
            expectedBaseProceeds,
            contributionPlusInterest - (bondAmount - basePaid),
            3e7
        );
        console.log("6.2");
        // WTF: I need to investigate this at a deeper level. It's not obvious
        // what the discrepancy is.
        //
        // TODO: Improve this bound.
        assertApproxEqAbs(baseProceeds, expectedBaseProceeds, 3e7);
        console.log("6.3");
        // TODO: Improve this bound.
        assertApproxEqAbs(
            baseToken.balanceOf(address(hyperdrive)),
            bondAmount +
                (FixedPointMath.ONE_18 + presentValueRatio())
                    .mulDown(hyperdrive.getPoolConfig().minimumShareReserves)
                    .mulDown(hyperdrive.getPoolInfo().sharePrice),
            3e7
        );
        console.log("6.4");
        assertEq(baseToken.balanceOf(alice), baseProceeds);
        console.log("6.5");
        console.log("test_remove_liquidity_short_trade: 7");

        // Ensure that the reserves were updated correctly.
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        assertEq(
            poolInfo.shareReserves,
            (FixedPointMath.ONE_18 + presentValueRatio()).mulDown(
                hyperdrive.getPoolConfig().minimumShareReserves
            )
        );
        assertEq(hyperdrive.calculateAPRFromReserves(), aprAfterTrade);
        console.log("test_remove_liquidity_short_trade: 8");

        // Ensure that Alice receives the right amount of withdrawal shares.
        assertApproxEqAbs(
            hyperdrive.balanceOf(AssetId._WITHDRAWAL_SHARE_ASSET_ID, alice),
            expectedWithdrawalShares,
            1
        );
        console.log("test_remove_liquidity_short_trade: 9");
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

    function calculateBaseProceeds(
        uint256 _shares
    ) internal view returns (uint256) {
        uint256 minimumShareReserves = hyperdrive
            .getPoolConfig()
            .minimumShareReserves;
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();
        uint256 shareProceeds = (poolInfo.shareReserves -
            minimumShareReserves -
            poolInfo.longsOutstanding.divDown(poolInfo.sharePrice)).mulDivDown(
                _shares,
                hyperdrive.totalSupply(AssetId._LP_ASSET_ID)
            );
        return shareProceeds.mulDown(poolInfo.sharePrice);
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
