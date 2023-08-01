// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { stdError } from "forge-std/StdError.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

contract CloseShortTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    function setUp() public override {
        super.setUp();

        // Start recording event logs.
        vm.recordLogs();
    }

    function test_close_short_failure_zero_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a short.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, ) = openShort(bob, bondAmount);

        // Attempt to close zero shorts. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.ZeroAmount.selector);
        hyperdrive.closeShort(maturityTime, 0, 0, bob, true);
    }

    function test_close_short_failure_invalid_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a short.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, ) = openShort(bob, bondAmount);

        // Attempt to close too many shorts. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(stdError.arithmeticError);
        hyperdrive.closeShort(maturityTime, bondAmount + 1, 0, bob, true);
    }

    function test_close_short_failure_invalid_timestamp() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a short.
        uint256 bondAmount = 10e18;
        openShort(bob, bondAmount);

        // Attempt to use a timestamp greater than the maximum range.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.InvalidTimestamp.selector);
        hyperdrive.closeShort(uint256(type(uint248).max) + 1, 1, 0, bob, true);
    }

    function test_close_short_failure_negative_interest(
        uint256 fixedRate,
        uint256 contribution,
        uint256 initialShortAmount,
        uint256 finalShortAmount
    ) external {
        // Initialize the pool. We use a relatively small fixed rate to ensure
        // that the maximum close short is constrained by the price cap of 1
        // rather than because of exceeding the long buffer.
        fixedRate = fixedRate.normalizeToRange(0.0001e18, 0.1e18);
        contribution = contribution.normalizeToRange(1_000e18, 500_000_000e18);
        initialize(alice, fixedRate, contribution);

        // Bob opens a short.
        initialShortAmount = initialShortAmount.normalizeToRange(
            0.00001e18,
            hyperdrive.calculateMaxShort() / 2
        );
        (uint256 maturityTime, ) = openShort(bob, initialShortAmount);

        // Celine opens a maximum long. This will prevent Bob from closing his
        // short by bringing the spot price very close to 1.
        openLong(celine, hyperdrive.calculateMaxLong());

        // Ensure that the max long results in spot price very close to 1 to
        // make sure that a negative interest failure is appropriate.
        assertLe(hyperdrive.calculateSpotPrice(), 1e18);
        assertApproxEqAbs(hyperdrive.calculateSpotPrice(), 1e18, 1e6);

        // Bob tries to close a small portion of his short. This should fail
        // the negative interest check.
        vm.stopPrank();
        vm.startPrank(bob);
        finalShortAmount = finalShortAmount.normalizeToRange(
            0.00001e18,
            initialShortAmount
        );
        vm.expectRevert(IHyperdrive.NegativeInterest.selector);
        hyperdrive.closeShort(maturityTime, finalShortAmount, 0, bob, true);
    }

    function test_close_short_immediately_with_regular_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Purchase some bonds.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, bondAmount);

        // Get the reserves and account balances before closing the short.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );

        // Immediately close the bonds.
        uint256 baseProceeds = closeShort(bob, maturityTime, bondAmount);

        // Verify that Bob doesn't end up with more base than he started with.
        assertGe(basePaid, baseProceeds);

        // Verify that the close short updates were correct.
        verifyCloseShort(
            poolInfoBefore,
            bobBaseBalanceBefore,
            hyperdriveBaseBalanceBefore,
            baseProceeds,
            bondAmount,
            maturityTime,
            false
        );
    }

    function test_close_short_immediately_with_small_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Short some bonds.
        uint256 bondAmount = .1e18;
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, bondAmount);

        // Get the reserves and account balances before closing the short.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );

        // Immediately close the bonds.
        uint256 baseProceeds = closeShort(bob, maturityTime, bondAmount);

        // Verify that Bob doesn't end up with more base than he started with.
        assertGe(basePaid, baseProceeds);

        // Verify that the close short updates were correct.
        verifyCloseShort(
            poolInfoBefore,
            bobBaseBalanceBefore,
            hyperdriveBaseBalanceBefore,
            baseProceeds,
            bondAmount,
            maturityTime,
            false
        );
    }

    // This stress tests the aggregate accounting by making the bond amount of
    // the second trade is off by 1 wei.
    function test_close_short_dust_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a short position.
        uint256 shortAmount = 10_000_000e18;
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, shortAmount);

        // Immediately close the bonds. We close the long in two transactions
        // to ensure that the close long function can handle small input amounts.
        uint256 baseProceeds = closeShort(bob, maturityTime, shortAmount / 2);
        baseProceeds += closeShort(bob, maturityTime, shortAmount / 2 - 1);

        // Verify that Bob doesn't end up with more base than he started with.
        assertGe(basePaid, baseProceeds);

        // Ensure that the average maturity time was updated correctly.
        assertEq(
            hyperdrive.getPoolInfo().shortAverageMaturityTime,
            maturityTime * 1e18
        );
    }

    function test_close_short_redeem_at_maturity_zero_variable_interest()
        external
    {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Short some bonds.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, ) = openShort(bob, bondAmount);

        // Get the reserves and account balances before closing the short.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );

        // The term passes.
        vm.warp(block.timestamp + 365 days);

        // Redeem the bonds.
        uint256 baseProceeds = closeShort(bob, maturityTime, bondAmount);

        // Verify that Bob doesn't receive any base from closing the short.
        assertEq(baseProceeds, 0);

        // Verify that the close short updates were correct.
        verifyCloseShort(
            poolInfoBefore,
            bobBaseBalanceBefore,
            hyperdriveBaseBalanceBefore,
            baseProceeds,
            bondAmount,
            maturityTime,
            false
        );
    }

    function test_close_short_redeem_negative_interest() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Short some bonds.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, ) = openShort(bob, bondAmount);

        // The term passes.
        advanceTime(POSITION_DURATION, -0.2e18);

        // Get the reserves and account balances before closing the short.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );

        // Redeem the bonds.
        uint256 baseProceeds = closeShort(bob, maturityTime, bondAmount);

        // Verify that Bob doesn't receive any base from closing the short.
        assertEq(baseProceeds, 0);

        // Verify that the close short updates were correct.
        verifyCloseShort(
            poolInfoBefore,
            bobBaseBalanceBefore,
            hyperdriveBaseBalanceBefore,
            baseProceeds,
            bondAmount,
            maturityTime,
            false
        );
    }

    function test_close_short_redeem_negative_interest_half_term() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Short some bonds.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, ) = openShort(bob, bondAmount);

        // The term passes and shares lose value
        advanceTime(POSITION_DURATION.mulDown(0.5e18), -0.2e18);

        // Get the reserves and account balances before closing the short.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );

        // Redeem the bonds.
        uint256 baseProceeds = closeShort(bob, maturityTime, bondAmount);

        // Verify that Bob doesn't receive any base from closing the short.
        assertEq(baseProceeds, 0);

        // Verify that the close short updates were correct.
        verifyCloseShort(
            poolInfoBefore,
            bobBaseBalanceBefore,
            hyperdriveBaseBalanceBefore,
            baseProceeds,
            bondAmount,
            maturityTime,
            false
        );
    }

    function test_close_short_negative_interest_at_close() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Short some bonds.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, ) = openShort(bob, bondAmount);

        // The term passes and shares lose value
        advanceTime(POSITION_DURATION, -0.2e18);

        // A checkpoint is created to lock in the close price.
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));

        // Another term passes and positive interest accrues.
        advanceTime(POSITION_DURATION, 0.5e18);

        // Get the reserves and account balances before closing the short.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );

        // Redeem the bonds.
        uint256 baseProceeds = closeShort(bob, maturityTime, bondAmount);

        // Verify that Bob doesn't receive any base from closing the short.
        assertEq(baseProceeds, 0);

        // Verify that the close long updates were correct.
        verifyCloseShort(
            poolInfoBefore,
            bobBaseBalanceBefore,
            hyperdriveBaseBalanceBefore,
            baseProceeds,
            bondAmount,
            maturityTime,
            true
        );
    }

    function test_close_short_max_loss() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Short some bonds.
        uint256 bondAmount = 1000e18;
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, bondAmount);

        // Advance and shares accrue 0% interest throughout the duration
        advanceTime(POSITION_DURATION, 0);
        assertEq(block.timestamp, maturityTime);

        // Get the reserves and account balances before closing the short.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );

        // Redeem the bonds.
        uint256 baseProceeds = closeShort(bob, maturityTime, bondAmount);

        // Should be near 100% of a loss
        assertApproxEqAbs(
            basePaid.sub(baseProceeds).divDown(basePaid),
            1e18,
            1e15 // TODO Large tolerance?
        );

        // Verify that the close short updates were correct.
        verifyCloseShort(
            poolInfoBefore,
            bobBaseBalanceBefore,
            hyperdriveBaseBalanceBefore,
            baseProceeds,
            bondAmount,
            maturityTime,
            false
        );
    }

    function test_short_fees_collect_on_close_at_maturity() external {
        uint256 fixedRate = 0.05e18;
        int256 variableRate = -0.05e18;
        uint256 contribution = 500_000_000e18;

        WithdrawalOverrides memory withdrawalOverrides = WithdrawalOverrides({
            asUnderlying: false,
            minSlippage: 0
        });

        DepositOverrides memory depositOverrides = DepositOverrides({
            asUnderlying: false,
            depositAmount: 10e18,
            minSlippage: 0,
            maxSlippage: type(uint256).max
        });

        // 1. Deploy a pool with zero fees
        IHyperdrive.PoolConfig memory config = testConfig(fixedRate);
        deploy(address(deployer), config);
        // Initialize the pool with a large amount of capital.
        initialize(alice, fixedRate, contribution);

        // 2. Open and then close a short
        (uint256 maturityTime, uint256 bondAmount) = openShort(
            bob,
            10e18,
            depositOverrides
        );
        advanceTime(POSITION_DURATION, variableRate);
        closeShort(bob, maturityTime, bondAmount, withdrawalOverrides);

        // 3. Record Share Reserves
        IHyperdrive.MarketState memory zeroFeeState = hyperdrive
            .getMarketState();

        // 4. deploy a pool with 100% curve fees and 100% gov fees (this is nice bc
        // it ensures that all the fees are credited to governance and thus subtracted
        // from the shareReserves
        config = testConfig(fixedRate);
        config.fees = IHyperdrive.Fees({
            curve: 0,
            flat: 1e18,
            governance: 1e18
        });
        deploy(address(deployer), config);
        initialize(alice, fixedRate, contribution);

        // 5. Open and close a short at maturity, advancing the time
        (maturityTime, bondAmount) = openShort(bob, 10e18, depositOverrides);
        advanceTime(POSITION_DURATION, variableRate);
        closeShort(bob, maturityTime, bondAmount, withdrawalOverrides);

        // 6. Record Share Reserves
        IHyperdrive.MarketState memory maxFeeState = hyperdrive
            .getMarketState();

        // Since the fees are subtracted from reserves and accounted for
        // seperately, this will be true
        assertEq(zeroFeeState.shareReserves, maxFeeState.shareReserves);

        uint256 govFees = hyperdrive.getUncollectedGovernanceFees();
        // Governance fees collected are non-zero
        assert(govFees > 1e5);

        // 7. deploy a pool with 100% curve fees and 0% gov fees
        config = testConfig(fixedRate);
        config.fees = IHyperdrive.Fees({ curve: 0, flat: 1e18, governance: 0 });
        // Deploy and initialize the new pool
        deploy(address(deployer), config);
        initialize(alice, fixedRate, contribution);

        // 8. Open and close another short at maturity as well, advancing the time
        (maturityTime, bondAmount) = openShort(bob, 10e18, depositOverrides);
        advanceTime(POSITION_DURATION, variableRate);
        closeShort(bob, maturityTime, bondAmount, withdrawalOverrides);

        // 9. Record Share Reserves
        IHyperdrive.MarketState memory maxFlatFeeState = hyperdrive
            .getMarketState();

        assertGt(maxFlatFeeState.shareReserves, zeroFeeState.shareReserves);
        assertGt(maxFlatFeeState.shareReserves, maxFeeState.shareReserves);
    }

    function verifyCloseShort(
        IHyperdrive.PoolInfo memory poolInfoBefore,
        uint256 bobBaseBalanceBefore,
        uint256 hyperdriveBaseBalanceBefore,
        uint256 baseProceeds,
        uint256 bondAmount,
        uint256 maturityTime,
        bool wasCheckpointed
    ) internal {
        // Ensure that one `CloseShort` event was emitted with the correct
        // arguments.
        {
            VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
                CloseShort.selector
            );
            assertEq(logs.length, 1);
            VmSafe.Log memory log = logs[0];
            assertEq(address(uint160(uint256(log.topics[1]))), bob);
            assertEq(
                uint256(log.topics[2]),
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, maturityTime)
            );
            (
                uint256 eventMaturityTime,
                uint256 eventBaseAmount,
                uint256 eventBondAmount
            ) = abi.decode(log.data, (uint256, uint256, uint256));
            assertEq(eventMaturityTime, maturityTime);
            assertEq(eventBaseAmount, baseProceeds);
            assertEq(eventBondAmount, bondAmount);
        }

        // Ensure that the correct amount of base was transferred from
        // Hyperdrive to Bob.
        assertEq(baseToken.balanceOf(bob), bobBaseBalanceBefore + baseProceeds);
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdriveBaseBalanceBefore - baseProceeds
        );

        // Verify that all of Bob's shorts were burned.
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    maturityTime
                ),
                bob
            ),
            0
        );

        // Retrieve the pool info after the trade.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();
        IHyperdrive.Checkpoint memory checkpoint = hyperdrive.getCheckpoint(
            maturityTime - POSITION_DURATION
        );

        // Verify that the other state was updated correctly.
        uint256 timeRemaining = HyperdriveUtils.calculateTimeRemaining(
            hyperdrive,
            maturityTime
        );

        if (wasCheckpointed) {
            assertEq(poolInfoAfter.shareReserves, poolInfoBefore.shareReserves);
            assertEq(
                poolInfoAfter.shortsOutstanding,
                poolInfoBefore.shortsOutstanding
            );
        } else {
            // TODO: Re-evaluate this. This is obviously correct; however, it may
            // be better to use HyperdriveMath or find an approximation so that we
            // aren't repeating ourselves.
            uint256 expectedShareReserves = poolInfoBefore.shareReserves +
                bondAmount.mulDivDown(
                    FixedPointMath.ONE_18 - timeRemaining,
                    poolInfoBefore.sharePrice
                ) +
                YieldSpaceMath.calculateSharesInGivenBondsOut(
                    poolInfoBefore.shareReserves,
                    poolInfoBefore.bondReserves,
                    bondAmount.mulDown(timeRemaining),
                    FixedPointMath.ONE_18 -
                        hyperdrive.getPoolConfig().timeStretch,
                    poolInfoBefore.sharePrice,
                    hyperdrive.getPoolConfig().initialSharePrice
                );
            assertApproxEqAbs(
                poolInfoAfter.shareReserves,
                expectedShareReserves,
                1e10
            );
            assertEq(
                poolInfoAfter.shortsOutstanding,
                poolInfoBefore.shortsOutstanding - bondAmount
            );
        }
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertEq(
            poolInfoAfter.longsOutstanding,
            poolInfoBefore.longsOutstanding
        );
        assertEq(poolInfoAfter.longAverageMaturityTime, 0);
        assertEq(poolInfoAfter.shortAverageMaturityTime, 0);
        assertEq(poolInfoAfter.shortBaseVolume, 0);
        assertEq(checkpoint.shortBaseVolume, 0);

        // TODO: Figure out how to test for this.
        //
        // Ensure that the bond reserves were updated to have the correct APR.
        // Due to the way that the flat part of the trade is applied, the bond
        // reserve updates may not exactly correspond to the amount of bonds
        // transferred; however, the pool's APR should be identical to the APR
        // that the bond amount transfer implies. The bond adjustment should be
        // equal to timeRemaining * bondAmount because the bond update decays as
        // the term progresses.
        // uint256 timeRemaining = calculateTimeRemaining(maturityTime);
        // assertApproxEqAbs(
        //     calculateAPRFromReserves(),
        //     HyperdriveMath.calculateAPRFromReserves(
        //         poolInfoAfter.shareReserves,
        //         poolInfoBefore.bondReserves - timeRemaining.mulDown(bondAmount),
        //         poolInfoAfter.lpTotalSupply,
        //         INITIAL_SHARE_PRICE,
        //         POSITION_DURATION,
        //         hyperdrive.timeStretch()
        //     ),
        //     5
        // );
    }
}
