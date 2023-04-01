// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { stdError } from "forge-std/StdError.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { HyperdriveTest, HyperdriveUtils, IHyperdrive } from "../../utils/HyperdriveTest.sol";

contract CloseLongTest is HyperdriveTest {
    using FixedPointMath for uint256;

    function test_close_long_failure_zero_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a long position.
        uint256 baseAmount = 10e18;
        (uint256 maturityTime, ) = openLong(bob, baseAmount);

        // Attempt to close zero longs. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.ZeroAmount.selector);
        hyperdrive.closeLong(maturityTime, 0, 0, bob, true);
    }

    function test_close_long_failure_invalid_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a long position.
        uint256 baseAmount = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, baseAmount);

        // Attempt to close too many longs. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(stdError.arithmeticError);
        hyperdrive.closeLong(maturityTime, bondAmount + 1, 0, bob, true);
    }

    function test_close_long_failure_invalid_timestamp() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a long position.
        uint256 baseAmount = 10e18;
        openLong(bob, baseAmount);

        // Attempt to use a timestamp greater than the maximum range.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(Errors.InvalidTimestamp.selector);
        hyperdrive.closeLong(uint256(type(uint248).max) + 1, 1, 0, bob, true);
    }

    function test_close_long_immediately_with_regular_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a long position.
        uint256 basePaid = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Get the reserves before closing the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Immediately close the bonds.
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // Verify that Bob didn't receive more base than he put in.
        assertLe(baseProceeds, basePaid);

        // Verify that the close long updates were correct.
        verifyCloseLong(
            poolInfoBefore,
            baseProceeds,
            bondAmount,
            maturityTime,
            false
        );
    }

    function test_close_long_immediately_with_small_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a long position.
        uint256 basePaid = .01e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Get the reserves before closing the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Immediately close the bonds.
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // Verify that Bob didn't receive more base than he put in.
        assertLe(baseProceeds, basePaid);

        // Verify that the close long updates were correct.
        verifyCloseLong(
            poolInfoBefore,
            baseProceeds,
            bondAmount,
            maturityTime,
            false
        );
    }

    function test_close_long_halfway_through_term() external {
        // Initialize the market.
        uint apr = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Bob opens a large long.
        uint256 basePaid = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Most of the term passes. The pool accrues interest at the current apr.
        uint256 timeDelta = 0.5e18;
        advanceTime(POSITION_DURATION.mulDown(timeDelta), int256(apr));

        // Get the reserves before closing the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Bob closes his long close to maturity.
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // Ensure that the realized APR is approximately equal to the pool APR.
        assertApproxEqAbs(
            HyperdriveUtils.calculateAPRFromRealizedPrice(
                basePaid,
                baseProceeds,
                FixedPointMath.ONE_18 - timeDelta
            ),
            apr,
            1e10
        );

        // Verify that the close long updates were correct.
        verifyCloseLong(
            poolInfoBefore,
            baseProceeds,
            bondAmount,
            maturityTime,
            false
        );
    }

    function test_close_long_redeem() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a long position.
        uint256 basePaid = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Term passes. The pool accrues interest at the current apr.
        uint256 timeDelta = 1e18;
        advanceTime(POSITION_DURATION.mulDown(timeDelta), int256(apr));

        // Get the reserves before closing the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Redeem the bonds
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // Verify that Bob received base equal to the full bond amount.
        assertApproxEqAbs(baseProceeds, bondAmount, 1);

        // Verify that the close long updates were correct.
        verifyCloseLong(
            poolInfoBefore,
            baseProceeds,
            bondAmount,
            maturityTime,
            false
        );
    }

    function test_close_long_redeem_negative_interest() external {
        uint256 fixedAPR = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedAPR, contribution);

        // Open a long position.
        uint256 basePaid = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Term passes. The pool accrues interest at the current apr.
        uint256 timeAdvanced = POSITION_DURATION;
        int256 apr = -0.3e18;
        advanceTime(timeAdvanced, apr);

        // Get the reserves before closing the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Redeem the bonds
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // Account the negative interest with the bondAmount as principal
        (uint256 bondFaceValue, ) = HyperdriveUtils.calculateCompoundInterest(
            bondAmount,
            apr,
            timeAdvanced
        );

        // As negative interest occurred over the duration, the long position
        // takes on the loss. As the "matured" bondAmount is implicitly an
        // amount of shares, the base value of those shares are negative
        // relative to what they were at the start of the term.
        uint256 matureBondsValue = bondAmount
            .divDown(hyperdrive.getPoolConfig().initialSharePrice)
            .mulDown(poolInfoBefore.sharePrice);

        // Verify that Bob received base equal to the full bond amount.
        assertApproxEqAbs(baseProceeds, bondFaceValue, 10);
        assertApproxEqAbs(baseProceeds, matureBondsValue, 10);

        // Verify that the close long updates were correct.
        verifyCloseLong(
            poolInfoBefore,
            baseProceeds,
            bondAmount,
            maturityTime,
            false
        );
    }

    function test_close_long_half_term_negative_interest() external {
        uint256 fixedAPR = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedAPR, contribution);

        // Open a long position.
        uint256 basePaid = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Term passes. The pool accrues negative interest.
        uint256 timeAdvanced = POSITION_DURATION.mulDown(0.5e18);
        int256 apr = -0.25e18;
        advanceTime(timeAdvanced, apr);

        // Get the reserves before closing the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Redeem the bonds
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // Initial share price
        uint256 initialSharePrice = hyperdrive
            .getPoolConfig()
            .initialSharePrice;

        // All mature bonds are redeemed at the equivalent amount of shares
        // held throughout the duration, losing capital
        uint256 matureBonds = bondAmount.mulDown(
            FixedPointMath.ONE_18.sub(
                HyperdriveUtils.calculateTimeRemaining(hyperdrive, maturityTime)
            )
        );
        uint256 matureBondsValue = matureBonds
            .divDown(initialSharePrice)
            .mulDown(poolInfoBefore.sharePrice);

        // Portion of immature bonds are sold on the YieldSpace curve
        uint256 immatureBonds = bondAmount - matureBonds;
        uint256 immatureBondsValue = YieldSpaceMath
            .calculateSharesOutGivenBondsIn(
                poolInfoBefore.shareReserves,
                poolInfoBefore.bondReserves,
                immatureBonds,
                FixedPointMath.ONE_18.sub(
                    hyperdrive.getPoolConfig().timeStretch
                ),
                poolInfoBefore.sharePrice,
                initialSharePrice
            )
            .mulDown(poolInfoBefore.sharePrice);

        // Account the negative interest with the bondAmount as principal
        (uint256 matureBondsFaceValue, ) = HyperdriveUtils
            .calculateCompoundInterest(matureBonds, apr, timeAdvanced);

        assertApproxEqAbs(
            baseProceeds,
            immatureBondsValue.add(matureBondsValue),
            6
        );
        assertApproxEqAbs(matureBondsValue, matureBondsFaceValue, 5);

        // Verify that the close long updates were correct.
        verifyCloseLong(
            poolInfoBefore,
            baseProceeds,
            bondAmount,
            maturityTime,
            false
        );
    }

    function test_close_long_negative_interest_at_close() external {
        uint256 fixedAPR = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedAPR, contribution);

        // Open a long position.
        uint256 basePaid = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // The term passes and the pool accrues negative interest.
        int256 apr = -0.25e18;
        advanceTime(POSITION_DURATION, apr);

        // A checkpoint is created to lock in the close price.
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));
        uint256 closeSharePrice = hyperdrive.getPoolInfo().sharePrice;

        // Another term passes and a large amount of positive interest accrues.
        advanceTime(POSITION_DURATION, 0.7e18);

        // Get the reserves before closing the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Redeem the bonds
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // Bond holders take a proportional haircut on any negative interest
        // that accrues.
        uint256 bondValue = bondAmount
            .divDown(hyperdrive.getPoolConfig().initialSharePrice)
            .mulDown(closeSharePrice);

        // Calculate the value of the bonds compounded at the negative APR.
        (uint256 bondFaceValue, ) = HyperdriveUtils.calculateCompoundInterest(
            bondAmount,
            apr,
            POSITION_DURATION
        );
        assertApproxEqAbs(baseProceeds, bondValue, 6);
        assertApproxEqAbs(bondValue, bondFaceValue, 5);

        // Verify that the close long updates were correct.
        verifyCloseLong(
            poolInfoBefore,
            baseProceeds,
            bondAmount,
            maturityTime,
            true
        );
    }

    function verifyCloseLong(
        IHyperdrive.PoolInfo memory poolInfoBefore,
        uint256 baseProceeds,
        uint256 bondAmount,
        uint256 maturityTime,
        bool wasCheckpointed
    ) internal {
        uint256 checkpointTime = maturityTime - POSITION_DURATION;

        // Verify that all of Bob's bonds were burned.
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
                bob
            ),
            0
        );

        // Verify that the other states were correct.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();

        IHyperdrive.Checkpoint memory checkpoint = hyperdrive.checkpoints(
            checkpointTime
        );
        if (wasCheckpointed) {
            assertEq(poolInfoAfter.shareReserves, poolInfoBefore.shareReserves);
            assertEq(
                poolInfoAfter.longsOutstanding,
                poolInfoBefore.longsOutstanding
            );
        } else {
            assertApproxEqAbs(
                poolInfoAfter.shareReserves,
                poolInfoBefore.shareReserves -
                    baseProceeds.divDown(poolInfoBefore.sharePrice),
                // TODO: This is a huge error bar.
                // 0.00000001 off or 1 wei
                poolInfoAfter.shareReserves.mulDown(100000000000) + 1
            );
            assertEq(
                poolInfoAfter.longsOutstanding,
                poolInfoBefore.longsOutstanding - bondAmount
            );
        }
        assertApproxEqAbs(
            poolInfoAfter.sharePrice,
            poolInfoBefore.sharePrice,
            1
        );
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertEq(poolInfoAfter.longAverageMaturityTime, 0);
        assertEq(poolInfoAfter.longBaseVolume, 0);
        assertEq(checkpoint.longBaseVolume, 0);
        assertEq(
            poolInfoAfter.shortsOutstanding,
            poolInfoBefore.shortsOutstanding
        );
        assertEq(poolInfoAfter.shortAverageMaturityTime, 0);
        assertEq(poolInfoAfter.shortBaseVolume, 0);
        assertEq(checkpoint.shortBaseVolume, 0);

        // TODO: Figure out how to test this without duplicating the logic.
        //
        // Ensure that the bond reserves were updated to have the correct APR.
        // Due to the way that the flat part of the trade is applied, the bond
        // reserve updates may not exactly correspond to the amount of bonds
        // transferred; however, the pool's APR should be identical to the APR
        // that the bond amount transfer implies. The adjustment should be equal
        // to timeRemaining * bondAmount.
        // uint256 timeRemaining = calculateTimeRemaining(maturityTime);
        // assertApproxEqAbs(
        //     calculateAPRFromReserves(),
        //     HyperdriveMath.calculateAPRFromReserves(
        //         poolInfoAfter.shareReserves,
        //         poolInfoBefore.bondReserves + timeRemaining.mulDown(bondAmount),
        //         poolInfoAfter.lpTotalSupply,
        //         INITIAL_SHARE_PRICE,
        //         POSITION_DURATION,
        //         hyperdrive.timeStretch()
        //     ),
        //     5
        // );
    }
}
