// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { stdError } from "forge-std/StdError.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "../../utils/HyperdriveTest.sol";

contract OpenLongTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_open_long_failure_zero_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to purchase bonds with zero base. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.ZeroAmount.selector);
        hyperdrive.openLong(0, 0, bob, true);
    }

    function test_open_long_failure_extreme_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to purchase more bonds than exist. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 baseAmount = hyperdrive.getPoolInfo().bondReserves;
        baseToken.mint(baseAmount);
        baseToken.approve(address(hyperdrive), baseAmount);
        vm.expectRevert(Errors.NegativeInterest.selector);
        hyperdrive.openLong(baseAmount, 0, bob, true);
    }

    function test_open_long() external {
        uint256 apr = 0.05e18;

        // Initialize the pools with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the reserves before opening the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Open a long.
        uint256 baseAmount = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, baseAmount);

        // Verify that the open long updated the state correctly.
        verifyOpenLong(
            poolInfoBefore,
            contribution,
            baseAmount,
            bondAmount,
            maturityTime,
            apr
        );
    }

    function test_open_long_with_small_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the reserves before opening the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Purchase a small amount of bonds.
        uint256 baseAmount = .01e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, baseAmount);

        // Verify that the open long updated the state correctly.
        verifyOpenLong(
            poolInfoBefore,
            contribution,
            baseAmount,
            bondAmount,
            maturityTime,
            apr
        );
    }

    function verifyOpenLong(
        IHyperdrive.PoolInfo memory poolInfoBefore,
        uint256 contribution,
        uint256 baseAmount,
        uint256 bondAmount,
        uint256 maturityTime,
        uint256 apr
    ) internal {
        // Verify that the open long updated the state correctly.
        _verifyOpenLong(
            bob,
            poolInfoBefore,
            contribution,
            baseAmount,
            bondAmount,
            maturityTime,
            apr
        );

        // Deploy and initialize a new pool with fees.
        deploy(alice, apr, 0.1e18, 0.1e18, 0, governance);
        initialize(alice, apr, contribution);

        // Open a long with fees.
        IHyperdrive.PoolInfo memory poolInfoBeforeWithFees = hyperdrive
            .getPoolInfo();
        (, uint256 bondAmountWithFees) = openLong(celine, baseAmount);

        _verifyOpenLong(
            celine,
            poolInfoBeforeWithFees,
            contribution,
            baseAmount,
            bondAmountWithFees,
            maturityTime,
            apr
        );

        // let's manually check that the fees are collected appropriately
        // curve fee = ((1 / p) - 1) * phi * c * d_z * t
        // p = 1 / (1 + r)
        // roughly ((1/.9523 - 1) * .1) * 10e18 * 1 = 5e16, or 10% of the 5% bond - base spread.
        uint256 p = (uint256(1 ether)).divDown(1 ether + 0.05 ether);
        uint256 phi = hyperdrive.getPoolConfig().curveFee;
        uint256 curveFeeAmount = (uint256(1 ether).divDown(p) - 1 ether)
            .mulDown(phi)
            .mulDown(baseAmount);

        IHyperdrive.PoolInfo memory poolInfoAfterWithFees = hyperdrive
            .getPoolInfo();

        // bondAmount is from the hyperdrive without the curve fee
        assertApproxEqAbs(
            poolInfoAfterWithFees.longsOutstanding,
            poolInfoBeforeWithFees.longsOutstanding +
                bondAmount -
                curveFeeAmount,
            10
        );
    }

    function _verifyOpenLong(
        address user,
        IHyperdrive.PoolInfo memory poolInfoBefore,
        uint256 contribution,
        uint256 baseAmount,
        uint256 bondAmount,
        uint256 maturityTime,
        uint256 apr
    ) internal {
        uint256 checkpointTime = maturityTime - POSITION_DURATION;

        // Verify the base transfers.
        assertEq(baseToken.balanceOf(user), 0);
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            contribution + baseAmount
        );

        // Verify that opening a long doesn't make the APR go up.
        uint256 realizedApr = HyperdriveUtils.calculateAPRFromRealizedPrice(
            baseAmount,
            bondAmount,
            FixedPointMath.ONE_18
        );
        assertGt(apr, realizedApr);

        // Ensure that the state changes to the share reserves were applied
        // correctly and that the other pieces of state were left untouched.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();

        assertEq(
            poolInfoAfter.shareReserves,
            poolInfoBefore.shareReserves +
                baseAmount.divDown(poolInfoBefore.sharePrice)
        );
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertEq(poolInfoAfter.sharePrice, poolInfoBefore.sharePrice);
        assertApproxEqAbs(
            poolInfoAfter.longsOutstanding,
            poolInfoBefore.longsOutstanding + bondAmount,
            10
        );

        // Ensure that the bond reserves were updated to have the correct APR.
        // Due to the way that the flat part of the trade is applied, the bond
        // reserve updates may not exactly correspond to the amount of bonds
        // transferred; however, the pool's APR should be identical to the APR
        // that the bond amount transfer implies.
        assertApproxEqAbs(
            HyperdriveUtils.calculateAPRFromReserves(hyperdrive),
            HyperdriveMath.calculateAPRFromReserves(
                poolInfoAfter.shareReserves,
                poolInfoBefore.bondReserves - bondAmount,
                INITIAL_SHARE_PRICE,
                POSITION_DURATION,
                hyperdrive.getPoolConfig().timeStretch
            ),
            5
        );

        // TODO: This problem gets much worse as the baseAmount to open a long gets smaller.
        // Figure out a solution to this.
        IHyperdrive.Checkpoint memory checkpoint = hyperdrive.checkpoints(
            checkpointTime
        );
        assertApproxEqAbs(
            poolInfoAfter.longAverageMaturityTime,
            maturityTime,
            100
        );
        assertEq(poolInfoAfter.longBaseVolume, baseAmount);
        assertEq(checkpoint.longBaseVolume, baseAmount);
        assertEq(
            poolInfoAfter.shortsOutstanding,
            poolInfoBefore.shortsOutstanding
        );
        assertEq(poolInfoAfter.shortAverageMaturityTime, 0);
        assertEq(poolInfoAfter.shortBaseVolume, 0);
        assertEq(checkpoint.shortBaseVolume, 0);
    }
}
