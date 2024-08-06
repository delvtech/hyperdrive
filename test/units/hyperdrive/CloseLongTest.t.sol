// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdError } from "forge-std/StdError.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "../../../contracts/src/libraries/YieldSpaceMath.sol";
import { MockHyperdrive } from "../../../contracts/test/MockHyperdrive.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract CloseLongTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for *;
    using Lib for *;

    function setUp() public override {
        super.setUp();

        // Start recording event logs.
        vm.recordLogs();
    }

    function test_close_long_failure_zero_amount() external {
        // Initialize the pool with a large amount of capital.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Open a long position.
        uint256 baseAmount = 10e18;
        (uint256 maturityTime, ) = openLong(bob, baseAmount);

        // Attempt to close zero longs. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.MinimumTransactionAmount.selector);
        hyperdrive.closeLong(
            maturityTime,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_close_long_failure_destination_zero_address() external {
        // Initialize the pool with a large amount of capital.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Open a long position.
        uint256 baseAmount = 30e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, baseAmount);

        // Alice attempts to set the destination to the zero address.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(IHyperdrive.RestrictedZeroAddress.selector);
        hyperdrive.closeLong(
            maturityTime,
            bondAmount,
            0,
            IHyperdrive.Options({
                destination: address(0),
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_close_long_failure_invalid_amount() external {
        // Initialize the pool with a large amount of capital.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Open a long position.
        uint256 baseAmount = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, baseAmount);

        // Attempt to close too many longs. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.InsufficientBalance.selector);
        hyperdrive.closeLong(
            maturityTime,
            bondAmount + 1,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_close_long_failure_zero_maturity() external {
        // Initialize the pool with a large amount of capital.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, fixedRate, contribution);

        // Open a long position.
        uint256 baseAmount = 30e18;
        openLong(bob, baseAmount);

        // Attempt to use a timestamp greater than the maximum range.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(stdError.arithmeticError);
        hyperdrive.closeLong(
            0,
            lpShares,
            0,
            IHyperdrive.Options({
                destination: alice,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_close_long_failure_invalid_timestamp() external {
        // Initialize the pool with a large amount of capital.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Open a long position.
        uint256 baseAmount = 10e18;
        openLong(bob, baseAmount);

        // Attempt to use a timestamp greater than the maximum range.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.InvalidTimestamp.selector);
        hyperdrive.closeLong(
            uint256(type(uint248).max) + 1,
            MINIMUM_TRANSACTION_AMOUNT,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_close_long_failure_insufficient_liquidity() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a small amount of capital.
        uint256 minimumShareReserves = hyperdrive
            .getPoolConfig()
            .minimumShareReserves;
        uint256 contribution = 10 * minimumShareReserves;
        initialize(alice, apr, contribution);

        // Open a long position.
        uint256 baseAmount = 2 * minimumShareReserves;
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, baseAmount);

        // Open a short position.
        uint256 shortAmount = hyperdrive.calculateMaxShort();
        openShort(bob, shortAmount);

        // Attempt to open a long that would bring the share reserves below the
        // minimum share reserves. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(IHyperdrive.InsufficientLiquidity.selector)
        );
        hyperdrive.closeLong(
            maturityTime,
            longAmount,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_close_long_failure_invalid_effective_share_reserves()
        external
    {
        uint256 apr = 0.05e18;

        // Initialize the pool with a small amount of capital.
        uint256 minimumShareReserves = hyperdrive
            .getPoolConfig()
            .minimumShareReserves;
        uint256 contribution = 10 * minimumShareReserves;
        initialize(alice, apr, contribution);

        // Alice opens a max short position.
        openShort(alice, hyperdrive.calculateMaxShort());

        // The term passes, and Alice's short matures.
        advanceTime(POSITION_DURATION, 0);
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint(), 0);

        // Open a long position.
        uint256 baseAmount = 2 * minimumShareReserves;
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, baseAmount);

        // Open a short position.
        uint256 shortAmount = minimumShareReserves;
        openShort(bob, shortAmount);

        // Attempt to open a long that would bring the share reserves below the
        // minimum share reserves. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(IHyperdrive.InsufficientLiquidity.selector)
        );
        hyperdrive.closeLong(
            maturityTime,
            longAmount,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_close_long_immediately_with_regular_amount() external {
        // Initialize the pool with a large amount of capital.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Open a long position.
        uint256 basePaid = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Get the reserves before closing the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );

        // Immediately close the bonds.
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // Verify that Bob didn't receive more base than he put in.
        assertLe(baseProceeds, basePaid);

        // Verify that the close long updates were correct.
        verifyCloseLong(
            TestCase({
                poolInfoBefore: poolInfoBefore,
                traderBaseBalanceBefore: bobBaseBalanceBefore,
                hyperdriveBaseBalanceBefore: hyperdriveBaseBalanceBefore,
                baseProceeds: baseProceeds,
                bondAmount: bondAmount,
                maturityTime: maturityTime,
                wasCheckpointed: false
            })
        );
    }

    function test_close_long_immediately_with_small_amount() external {
        // Initialize the pool with a large amount of capital.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Open a long position.
        uint256 basePaid = .01e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Get the reserves before closing the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );

        // Immediately close the bonds.
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // Verify that Bob didn't receive more base than he put in.
        assertLe(baseProceeds, basePaid);

        // Verify that the close long updates were correct.
        verifyCloseLong(
            TestCase({
                poolInfoBefore: poolInfoBefore,
                traderBaseBalanceBefore: bobBaseBalanceBefore,
                hyperdriveBaseBalanceBefore: hyperdriveBaseBalanceBefore,
                baseProceeds: baseProceeds,
                bondAmount: bondAmount,
                maturityTime: maturityTime,
                wasCheckpointed: false
            })
        );
    }

    // This stress tests the aggregate accounting by making the bond amount of
    // the second trade off by 1 wei.
    function test_close_long_dust_amount() external {
        // Initialize the pool with a large amount of capital.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Open a long position.
        uint256 basePaid = 10_000_000e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Immediately close the bonds. We close the long in two transactions
        // to ensure that the close long function can handle small input amounts.
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount / 2);
        baseProceeds += closeLong(bob, maturityTime, bondAmount / 2 - 1);

        // Verify that Bob didn't receive more base than he put in.
        assertLe(baseProceeds, basePaid);

        // Ensure that the average maturity time was updated correctly.
        assertEq(
            hyperdrive.getPoolInfo().longAverageMaturityTime,
            maturityTime * 1e18
        );
    }

    function test_close_long_halfway_through_term() external {
        // Initialize the market.
        uint fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Bob opens a large long.
        uint256 basePaid = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Most of the term passes. The variable rate equals the fixed rate.
        uint256 timeDelta = 0.5e18;
        advanceTime(POSITION_DURATION.mulDown(timeDelta), int256(fixedRate));

        // Get the reserves before closing the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );

        // Bob closes his long close to maturity.
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // calculate the amount of time that passed since the last checkpoint
        uint256 checkpointDistance = block.timestamp -
            HyperdriveUtils.latestCheckpoint(hyperdrive);

        // Ensure that the realized rate is approximately equal to the spot rate.
        assertApproxEqAbs(
            HyperdriveUtils.calculateAPRFromRealizedPrice(
                basePaid,
                baseProceeds,
                ONE - timeDelta - checkpointDistance.divDown(POSITION_DURATION)
            ),
            fixedRate,
            1e10
        );

        // Verify that the close long updates were correct.
        verifyCloseLong(
            TestCase({
                poolInfoBefore: poolInfoBefore,
                traderBaseBalanceBefore: bobBaseBalanceBefore,
                hyperdriveBaseBalanceBefore: hyperdriveBaseBalanceBefore,
                baseProceeds: baseProceeds,
                bondAmount: bondAmount,
                maturityTime: maturityTime,
                wasCheckpointed: false
            })
        );
    }

    function test_close_long_redeem() external {
        // Initialize the pool with a large amount of capital.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Open a long position.
        uint256 basePaid = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Term passes. The pool accrues interest at the current apr.
        uint256 timeDelta = 1e18;
        advanceTime(POSITION_DURATION.mulDown(timeDelta), int256(fixedRate));

        // Get the reserves before closing the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );

        // Redeem the bonds
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // Verify that Bob received base equal to the full bond amount.
        assertLe(baseProceeds, bondAmount);
        assertApproxEqAbs(baseProceeds, bondAmount, 2);

        // Verify that the close long updates were correct.
        verifyCloseLong(
            TestCase({
                poolInfoBefore: poolInfoBefore,
                traderBaseBalanceBefore: bobBaseBalanceBefore,
                hyperdriveBaseBalanceBefore: hyperdriveBaseBalanceBefore,
                baseProceeds: baseProceeds,
                bondAmount: bondAmount,
                maturityTime: maturityTime,
                wasCheckpointed: false
            })
        );
    }

    function test_close_long_redeem_negative_interest() external {
        // Initialize the pool with a large amount of capital.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Open a long position.
        uint256 basePaid = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Term passes. The pool accrues interest at the current apr.
        uint256 timeAdvanced = POSITION_DURATION;
        int256 apr = -0.3e18;
        advanceTime(timeAdvanced, apr);

        // Get the reserves before closing the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );

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
            .divDown(hyperdrive.getPoolConfig().initialVaultSharePrice)
            .mulDown(poolInfoBefore.vaultSharePrice);

        // Verify that Bob received base equal to the full bond amount.
        assertApproxEqAbs(baseProceeds, bondFaceValue, 10);
        assertApproxEqAbs(baseProceeds, matureBondsValue, 10);

        // Verify that the close long updates were correct.
        verifyCloseLong(
            TestCase({
                poolInfoBefore: poolInfoBefore,
                traderBaseBalanceBefore: bobBaseBalanceBefore,
                hyperdriveBaseBalanceBefore: hyperdriveBaseBalanceBefore,
                baseProceeds: baseProceeds,
                bondAmount: bondAmount,
                maturityTime: maturityTime,
                wasCheckpointed: false
            })
        );
    }

    function test_close_long_half_term_negative_interest() external {
        // Initialize the pool with a large amount of capital.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Open a long position.
        uint256 basePaid = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Term passes. The pool accrues negative interest.
        uint256 timeAdvanced = POSITION_DURATION.mulDown(0.5e18);
        int256 apr = -0.25e18;
        advanceTime(timeAdvanced, apr);

        // Get the reserves before closing the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );

        // Redeem the bonds
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // Initial share price
        uint256 initialVaultSharePrice = hyperdrive
            .getPoolConfig()
            .initialVaultSharePrice;

        // Ensure that the base proceeds are correct.
        {
            // All mature bonds are redeemed at the equivalent amount of shares
            // held throughout the duration, losing capital
            uint256 matureBonds = bondAmount.mulDown(
                ONE -
                    HyperdriveUtils.calculateTimeRemaining(
                        hyperdrive,
                        maturityTime
                    )
            );
            uint256 bondsValue = matureBonds;

            // Portion of immature bonds are sold on the YieldSpace curve
            uint256 immatureBonds = bondAmount - matureBonds;
            bondsValue += YieldSpaceMath
                .calculateSharesOutGivenBondsInDown(
                    HyperdriveMath.calculateEffectiveShareReserves(
                        poolInfoBefore.shareReserves,
                        poolInfoBefore.shareAdjustment
                    ),
                    poolInfoBefore.bondReserves,
                    immatureBonds,
                    ONE - hyperdrive.getPoolConfig().timeStretch,
                    poolInfoBefore.vaultSharePrice,
                    initialVaultSharePrice
                )
                .mulDown(poolInfoBefore.vaultSharePrice);

            bondsValue = bondsValue.divDown(initialVaultSharePrice).mulDown(
                poolInfoBefore.vaultSharePrice
            );

            assertLe(baseProceeds, bondsValue);
            assertApproxEqAbs(baseProceeds, bondsValue, 1);
        }

        // Verify that the close long updates were correct.
        verifyCloseLong(
            TestCase({
                poolInfoBefore: poolInfoBefore,
                traderBaseBalanceBefore: bobBaseBalanceBefore,
                hyperdriveBaseBalanceBefore: hyperdriveBaseBalanceBefore,
                baseProceeds: baseProceeds,
                bondAmount: bondAmount,
                maturityTime: maturityTime,
                wasCheckpointed: false
            })
        );
    }

    // This test ensures that the reserves are updated correctly when longs are
    // closed at maturity with negative interest.
    function test_close_long_negative_interest_at_maturity() external {
        // Initialize the pool with a large amount of capital.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Open a long position.
        uint256 basePaid = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // The term passes and the pool accrues negative interest.
        int256 apr = -0.25e18;
        advanceTime(POSITION_DURATION, apr);

        // Get the reserves and base balances before closing the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );

        // Bob redeems the bonds. Ensure that the return value matches the
        // amount of base transferred to Bob.
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);
        uint256 closeVaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;

        // Bond holders take a proportional haircut on any negative interest
        // that accrues.
        uint256 bondValue = bondAmount
            .divDown(hyperdrive.getPoolConfig().initialVaultSharePrice)
            .mulDown(closeVaultSharePrice);

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
            TestCase({
                poolInfoBefore: poolInfoBefore,
                traderBaseBalanceBefore: bobBaseBalanceBefore,
                hyperdriveBaseBalanceBefore: hyperdriveBaseBalanceBefore,
                baseProceeds: baseProceeds,
                bondAmount: bondAmount,
                maturityTime: maturityTime,
                wasCheckpointed: false
            })
        );
    }

    // This test ensures that waiting to close your longs won't avoid negative
    // interest that occurred while the long was open.
    function test_close_long_negative_interest_before_maturity() external {
        // Initialize the pool with a large amount of capital.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Open a long position.
        uint256 basePaid = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // The term passes and the pool accrues negative interest.
        int256 apr = -0.25e18;
        advanceTime(POSITION_DURATION, apr);

        // A checkpoint is created to lock in the close price.
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive), 0);
        uint256 closeVaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;

        // Another term passes and a large amount of positive interest accrues.
        advanceTime(POSITION_DURATION, 0.7e18);
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint(), 0);

        // Get the reserves and base balances before closing the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );

        // Bob redeems the bonds. Ensure that the return value matches the
        // amount of base transferred to Bob.
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // Bond holders take a proportional haircut on any negative interest
        // that accrues.
        uint256 bondValue = bondAmount
            .divDown(hyperdrive.getPoolConfig().initialVaultSharePrice)
            .mulDown(closeVaultSharePrice);

        // Calculate the value of the bonds compounded at the negative APR.
        (uint256 bondFaceValue, ) = HyperdriveUtils.calculateCompoundInterest(
            bondAmount,
            apr,
            POSITION_DURATION
        );

        assertLe(baseProceeds, bondValue);
        assertApproxEqAbs(baseProceeds, bondValue, 7);
        assertApproxEqAbs(bondValue, bondFaceValue, 5);

        // Verify that the close long updates were correct.
        verifyCloseLong(
            TestCase({
                poolInfoBefore: poolInfoBefore,
                traderBaseBalanceBefore: bobBaseBalanceBefore,
                hyperdriveBaseBalanceBefore: hyperdriveBaseBalanceBefore,
                baseProceeds: baseProceeds,
                bondAmount: bondAmount,
                maturityTime: maturityTime,
                wasCheckpointed: true
            })
        );
    }

    // This test ensures that waiting to close your longs won't avoid negative
    // interest that occurred after the long was open while it was a zombie.
    function test_close_long_negative_interest_after_maturity() external {
        // Initialize the pool with a large amount of capital.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Open a long position.
        uint256 basePaid = 10e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // The term passes and the pool accrues negative interest.
        int256 apr = 0.5e18;
        advanceTime(POSITION_DURATION, apr);

        // A checkpoint is created to lock in the close price.
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive), 0);
        uint256 closeVaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;

        // Another term passes and a large amount of negative interest accrues.
        int256 negativeApr = -0.2e18;
        advanceTime(POSITION_DURATION, negativeApr);
        hyperdrive.checkpoint(hyperdrive.latestCheckpoint(), 0);

        // Get the reserves and base balances before closing the long.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );

        // Bob redeems the bonds. Ensure that the return value matches the
        // amount of base transferred to Bob.
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // Bond holders take a proportional haircut on any negative interest
        // that accrues.
        uint256 bondValue = bondAmount.divDown(closeVaultSharePrice).mulDown(
            hyperdrive.getPoolInfo().vaultSharePrice
        );

        // Calculate the value of the bonds compounded at the negative APR.
        (uint256 bondFaceValue, ) = HyperdriveUtils.calculateCompoundInterest(
            bondAmount,
            negativeApr,
            POSITION_DURATION
        );

        assertApproxEqAbs(baseProceeds, bondValue, 6);
        assertApproxEqAbs(bondValue, bondFaceValue, 5);

        // Verify that the close long updates were correct.
        verifyCloseLong(
            TestCase({
                poolInfoBefore: poolInfoBefore,
                traderBaseBalanceBefore: bobBaseBalanceBefore,
                hyperdriveBaseBalanceBefore: hyperdriveBaseBalanceBefore,
                baseProceeds: baseProceeds,
                bondAmount: bondAmount,
                maturityTime: maturityTime,
                wasCheckpointed: true
            })
        );
    }

    function test_close_long_after_matured_long() external {
        // Initialize the pool with a large amount of capital.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // A large long is opened and held until maturity. This should decrease
        // the share adjustment by the long amount.
        int256 shareAdjustmentBefore = hyperdrive.getPoolInfo().shareAdjustment;
        (, uint256 longAmount) = openLong(
            celine,
            hyperdrive.calculateMaxLong() / 2
        );
        advanceTime(hyperdrive.getPoolConfig().positionDuration, 0);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive), 0);
        assertEq(
            hyperdrive.getPoolInfo().shareAdjustment,
            shareAdjustmentBefore - int256(longAmount)
        );

        // Bob opens a small long.
        uint256 basePaid = 1_000_000e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Celine opens a large short. This will make it harder for Bob to close
        // his long (however there should be adequate liquidity left).
        openShort(celine, hyperdrive.calculateMaxShort() / 2);

        // Bob is able to close his long.
        closeLong(bob, maturityTime, bondAmount);
    }

    // Test that the close long function works correctly after a matured short
    // is closed.
    function test_close_long_after_matured_short() external {
        // Initialize the pool with a large amount of capital.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // A large short is opened and held until maturity. This should increase
        // the share adjustment by the short amount.
        int256 shareAdjustmentBefore = hyperdrive.getPoolInfo().shareAdjustment;
        uint256 shortAmount = hyperdrive.calculateMaxShort() / 2;
        openShort(celine, shortAmount);
        advanceTime(hyperdrive.getPoolConfig().positionDuration, 0);
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive), 0);
        assertEq(
            hyperdrive.getPoolInfo().shareAdjustment,
            shareAdjustmentBefore + int256(shortAmount)
        );

        // Bob opens a small long.
        uint256 basePaid = 1_000_000e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Celine opens a large short. This will make it harder for Bob to close
        // his long (however there should be adequate liquidity left).
        openShort(celine, hyperdrive.calculateMaxShort() / 2);

        // Bob is able to close his long.
        closeLong(bob, maturityTime, bondAmount);
    }

    function test_long_fees_collect_on_close_at_maturity() external {
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;

        // 1. Deploy a pool with zero fees
        IHyperdrive.PoolConfig memory config = testConfig(
            fixedRate,
            POSITION_DURATION
        );
        deploy(address(deployer), config);
        // Initialize the pool with a large amount of capital.
        initialize(alice, fixedRate, contribution);

        // 2. A long is opened and the term passes. The long is closed at maturity.
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, 10e18);
        advanceTime(POSITION_DURATION, int256(fixedRate));
        closeLong(bob, maturityTime, bondAmount);

        // 3. Record Share Reserves
        IHyperdrive.MarketState memory zeroFeeState = hyperdrive
            .getMarketState();

        // 4. deploy a pool with 100% curve fees and 100% gov fees (this is nice bc
        // it ensures that all the fees are credited to governance and thus subtracted
        // from the shareReserves
        config = testConfig(fixedRate, POSITION_DURATION);
        config.fees = IHyperdrive.Fees({
            curve: 0,
            flat: 0.01e18,
            governanceLP: 1e18,
            governanceZombie: 1e18
        });
        deploy(address(deployer), config);
        initialize(alice, fixedRate, contribution);

        // 5. Open and close a Long advancing it to maturity
        (maturityTime, bondAmount) = openLong(bob, 10e18);
        advanceTime(POSITION_DURATION, int256(fixedRate));
        closeLong(bob, maturityTime, bondAmount);

        // 6. Record Share Reserves
        IHyperdrive.MarketState memory maxFeeState = hyperdrive
            .getMarketState();

        uint256 govFees = hyperdrive.getUncollectedGovernanceFees();
        // Governance fees collected are non-zero
        assert(govFees > 1e5);

        // 7. deploy a pool with 100% curve fees and 0% gov fees
        config = testConfig(fixedRate, POSITION_DURATION);
        config.fees = IHyperdrive.Fees({
            curve: 0,
            flat: 0.01e18,
            governanceLP: 0,
            governanceZombie: 0
        });
        // Deploy and initialize the new pool
        deploy(address(deployer), config);
        initialize(alice, fixedRate, contribution);

        // 8. Open and close another Long at maturity advancing the time
        (maturityTime, bondAmount) = openLong(bob, 10e18);
        advanceTime(POSITION_DURATION, int256(fixedRate));
        closeLong(bob, maturityTime, bondAmount);

        // 9. Record Share Reserves
        IHyperdrive.MarketState memory maxFlatFeeState = hyperdrive
            .getMarketState();

        // The fees are subtracted from reserves and accounted for
        // separately, so this will be true.
        assertEq(zeroFeeState.shareReserves, maxFeeState.shareReserves);
        assertGt(maxFlatFeeState.shareReserves, zeroFeeState.shareReserves);
    }

    function test_close_long_destination() external {
        // Initialize the pool with a large amount of capital.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Bob opens a long.
        uint256 basePaid = 1_000_000e18;
        (uint256 maturityTime, uint256 bondAmount) = openLong(bob, basePaid);

        // Bob closes his long and sends the proceeds to Celine.
        uint256 baseProceeds = closeLong(
            bob,
            maturityTime,
            bondAmount,
            WithdrawalOverrides({
                asBase: true,
                destination: celine,
                minSlippage: 0,
                extraData: new bytes(0)
            })
        );

        // Ensure that the correct event was emitted.
        verifyCloseLongEvent(
            bob,
            celine,
            maturityTime,
            bondAmount,
            baseProceeds
        );

        // Ensure that the proceeds were sent to Celine.
        assertEq(baseToken.balanceOf(bob), 0);
        assertEq(baseToken.balanceOf(celine), baseProceeds);
    }

    struct TestCase {
        IHyperdrive.PoolInfo poolInfoBefore;
        uint256 traderBaseBalanceBefore;
        uint256 hyperdriveBaseBalanceBefore;
        uint256 baseProceeds;
        uint256 bondAmount;
        uint256 maturityTime;
        bool wasCheckpointed;
    }

    function verifyCloseLong(TestCase memory testCase) internal {
        // Ensure that one `CloseLong` event was emitted with the correct
        // arguments.
        verifyCloseLongEvent(
            bob,
            bob,
            testCase.maturityTime,
            testCase.bondAmount,
            testCase.baseProceeds
        );

        // Ensure that the correct amount of base was transferred.
        assertEq(
            baseToken.balanceOf(bob),
            testCase.traderBaseBalanceBefore + testCase.baseProceeds
        );
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            testCase.hyperdriveBaseBalanceBefore - testCase.baseProceeds
        );

        // Verify that all of Bob's bonds were burned.
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Long,
                    testCase.maturityTime
                ),
                bob
            ),
            0
        );

        // Verify that the other states were correct.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();
        if (testCase.wasCheckpointed) {
            assertEq(
                poolInfoAfter.shareReserves,
                testCase.poolInfoBefore.shareReserves
            );
            assertEq(
                poolInfoAfter.shareAdjustment,
                testCase.poolInfoBefore.shareAdjustment
            );
            assertEq(
                poolInfoAfter.longsOutstanding,
                testCase.poolInfoBefore.longsOutstanding
            );
        } else {
            assertApproxEqAbs(
                poolInfoAfter.shareReserves,
                testCase.poolInfoBefore.shareReserves -
                    testCase.baseProceeds.divDown(
                        testCase.poolInfoBefore.vaultSharePrice
                    ),
                10
            );
            assertEq(
                poolInfoAfter.longsOutstanding,
                testCase.poolInfoBefore.longsOutstanding - testCase.bondAmount
            );

            // There are two components of the share adjustment delta. The first
            // is from negative interest and the second is from the flat update.
            // Without re-doing the calculation here, we can check that the
            // share adjustment delta is greater than or equal to the flat update
            // and verify that k remained invariant.
            uint256 initialVaultSharePrice = hyperdrive
                .getPoolConfig()
                .initialVaultSharePrice;
            uint256 timeElapsed = ONE -
                hyperdrive.calculateTimeRemaining(testCase.maturityTime);
            uint256 shareAdjustmentDelta = testCase.bondAmount.mulDivDown(
                timeElapsed,
                poolInfoAfter.vaultSharePrice
            );
            if (poolInfoAfter.vaultSharePrice < initialVaultSharePrice) {
                shareAdjustmentDelta = shareAdjustmentDelta.mulDivDown(
                    poolInfoAfter.vaultSharePrice,
                    initialVaultSharePrice
                );
            }
            assertGe(
                poolInfoAfter.shareAdjustment,
                testCase.poolInfoBefore.shareAdjustment -
                    int256(shareAdjustmentDelta)
            );
            assertApproxEqAbs(
                YieldSpaceMath.kDown(
                    HyperdriveMath.calculateEffectiveShareReserves(
                        poolInfoAfter.shareReserves,
                        poolInfoAfter.shareAdjustment
                    ),
                    poolInfoAfter.bondReserves,
                    ONE - hyperdrive.getPoolConfig().timeStretch,
                    poolInfoAfter.vaultSharePrice,
                    initialVaultSharePrice
                ),
                YieldSpaceMath.kDown(
                    HyperdriveMath.calculateEffectiveShareReserves(
                        testCase.poolInfoBefore.shareReserves,
                        testCase.poolInfoBefore.shareAdjustment
                    ),
                    testCase.poolInfoBefore.bondReserves,
                    ONE - hyperdrive.getPoolConfig().timeStretch,
                    testCase.poolInfoBefore.vaultSharePrice,
                    initialVaultSharePrice
                ),
                1e10
            );
        }
        assertEq(
            poolInfoAfter.vaultSharePrice,
            testCase.poolInfoBefore.vaultSharePrice
        );
        assertEq(
            poolInfoAfter.lpTotalSupply,
            testCase.poolInfoBefore.lpTotalSupply
        );
        assertEq(poolInfoAfter.longAverageMaturityTime, 0);
        assertEq(
            poolInfoAfter.shortsOutstanding,
            testCase.poolInfoBefore.shortsOutstanding
        );
        assertEq(poolInfoAfter.shortAverageMaturityTime, 0);
    }

    function verifyCloseLongEvent(
        address trader,
        address destination,
        uint256 maturityTime,
        uint256 bondAmount,
        uint256 baseProceeds
    ) internal {
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            CloseLong.selector
        );
        assertEq(logs.length, 1);
        VmSafe.Log memory log = logs[0];
        assertEq(address(uint160(uint256(log.topics[1]))), trader);
        assertEq(address(uint160(uint256(log.topics[2]))), destination);
        assertEq(
            uint256(log.topics[3]),
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime)
        );
        (
            uint256 eventMaturityTime,
            uint256 eventAmount,
            uint256 eventVaultSharePrice,
            bool eventAsBase,
            uint256 eventBondAmount
        ) = abi.decode(log.data, (uint256, uint256, uint256, bool, uint256));
        assertEq(eventMaturityTime, maturityTime);
        assertEq(eventAmount, baseProceeds);
        assertEq(
            eventVaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice
        );
        assertEq(eventAsBase, true);
        assertEq(eventBondAmount, bondAmount);
    }
}
