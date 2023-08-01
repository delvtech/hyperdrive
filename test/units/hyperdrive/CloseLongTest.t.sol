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

contract CloseLongTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;

    function setUp() public override {
        super.setUp();

        // Start recording event logs.
        vm.recordLogs();
    }

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
        vm.expectRevert(IHyperdrive.ZeroAmount.selector);
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

    function test_close_long_failure_zero_maturity() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        uint256 lpShares = initialize(alice, apr, contribution);

        // Open a long position.
        uint256 baseAmount = 30e18;
        openLong(bob, baseAmount);

        // Attempt to use a timestamp greater than the maximum range.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(stdError.arithmeticError);
        hyperdrive.closeLong(0, lpShares, 0, alice, true);
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
        vm.expectRevert(IHyperdrive.InvalidTimestamp.selector);
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
            poolInfoBefore,
            bobBaseBalanceBefore,
            hyperdriveBaseBalanceBefore,
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
    // the second trade off by 1 wei.
    function test_close_long_dust_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

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

        // Ensure that the average open share price was updated correctly.
        assertEq(
            hyperdrive.getCheckpoint(block.timestamp).longSharePrice,
            hyperdrive.getPoolInfo().sharePrice
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
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );

        // Bob closes his long close to maturity.
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // calculate the amount of time that passed since the last checkpoint
        uint256 checkpointDistance = block.timestamp -
            HyperdriveUtils.latestCheckpoint(hyperdrive);

        // Ensure that the realized APR is approximately equal to the pool APR.
        assertApproxEqAbs(
            HyperdriveUtils.calculateAPRFromRealizedPrice(
                basePaid,
                baseProceeds,
                FixedPointMath.ONE_18 -
                    timeDelta -
                    checkpointDistance.divDown(POSITION_DURATION)
            ),
            apr,
            1e10
        );

        // Verify that the close long updates were correct.
        verifyCloseLong(
            poolInfoBefore,
            bobBaseBalanceBefore,
            hyperdriveBaseBalanceBefore,
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
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );

        // Redeem the bonds
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // Verify that Bob received base equal to the full bond amount.
        assertApproxEqAbs(baseProceeds, bondAmount, 1);

        // Verify that the close long updates were correct.
        verifyCloseLong(
            poolInfoBefore,
            bobBaseBalanceBefore,
            hyperdriveBaseBalanceBefore,
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
            .divDown(hyperdrive.getPoolConfig().initialSharePrice)
            .mulDown(poolInfoBefore.sharePrice);

        // Verify that Bob received base equal to the full bond amount.
        assertApproxEqAbs(baseProceeds, bondFaceValue, 10);
        assertApproxEqAbs(baseProceeds, matureBondsValue, 10);

        // Verify that the close long updates were correct.
        verifyCloseLong(
            poolInfoBefore,
            bobBaseBalanceBefore,
            hyperdriveBaseBalanceBefore,
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
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );

        // Redeem the bonds
        uint256 baseProceeds = closeLong(bob, maturityTime, bondAmount);

        // Initial share price
        uint256 initialSharePrice = hyperdrive
            .getPoolConfig()
            .initialSharePrice;

        // Ensure that the base proceeds are correct.
        {
            // All mature bonds are redeemed at the equivalent amount of shares
            // held throughout the duration, losing capital
            uint256 matureBonds = bondAmount.mulDown(
                FixedPointMath.ONE_18.sub(
                    HyperdriveUtils.calculateTimeRemaining(
                        hyperdrive,
                        maturityTime
                    )
                )
            );
            uint256 bondsValue = matureBonds;

            // Portion of immature bonds are sold on the YieldSpace curve
            uint256 immatureBonds = bondAmount - matureBonds;
            bondsValue += YieldSpaceMath
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

            bondsValue = bondsValue.divDown(initialSharePrice).mulDown(
                poolInfoBefore.sharePrice
            );

            assertEq(baseProceeds, bondsValue);
        }

        // Verify that the close long updates were correct.
        verifyCloseLong(
            poolInfoBefore,
            bobBaseBalanceBefore,
            hyperdriveBaseBalanceBefore,
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
            bobBaseBalanceBefore,
            hyperdriveBaseBalanceBefore,
            baseProceeds,
            bondAmount,
            maturityTime,
            true
        );
    }

    function test_long_fees_collect_on_close() external {
        uint256 fixedRate = 0.05e18;
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

        // 2. Open and then close a Long
        (uint256 maturityTime, uint256 bondAmount) = openLong(
            bob,
            10e18,
            depositOverrides
        );
        advanceTime(POSITION_DURATION, int256(fixedRate));
        closeLong(bob, maturityTime, bondAmount, withdrawalOverrides);

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

        // 5. Open and close a Long
        (maturityTime, bondAmount) = openLong(bob, 10e18, depositOverrides);
        advanceTime(POSITION_DURATION, int256(fixedRate));
        closeLong(bob, maturityTime, bondAmount, withdrawalOverrides);

        // 6. Record Share Reserves
        IHyperdrive.MarketState memory maxFeeState = hyperdrive
            .getMarketState();

        // The fees are subtracted from reserves and accounted for
        // separately, so this will be true.
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

        // 8. Open and close another Long
        (maturityTime, bondAmount) = openLong(bob, 10e18, depositOverrides);
        advanceTime(POSITION_DURATION, int256(fixedRate));
        closeLong(bob, maturityTime, bondAmount, withdrawalOverrides);

        // 9. Record Share Reserves
        IHyperdrive.MarketState memory maxFlatFeeState = hyperdrive
            .getMarketState();

        assertGt(maxFlatFeeState.shareReserves, zeroFeeState.shareReserves);
        assertGt(maxFlatFeeState.shareReserves, maxFeeState.shareReserves);
    }

    function verifyCloseLong(
        IHyperdrive.PoolInfo memory poolInfoBefore,
        uint256 traderBaseBalanceBefore,
        uint256 hyperdriveBaseBalanceBefore,
        uint256 baseProceeds,
        uint256 bondAmount,
        uint256 maturityTime,
        bool wasCheckpointed
    ) internal {
        uint256 checkpointTime = maturityTime - POSITION_DURATION;

        // Ensure that one `CloseLong` event was emitted with the correct
        // arguments.
        {
            VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
                CloseLong.selector
            );
            assertEq(logs.length, 1);
            VmSafe.Log memory log = logs[0];
            assertEq(address(uint160(uint256(log.topics[1]))), bob);
            assertEq(
                uint256(log.topics[2]),
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime)
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

        // Ensure that the correct amount of base was transferred.
        assertEq(
            baseToken.balanceOf(bob),
            traderBaseBalanceBefore + baseProceeds
        );
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            hyperdriveBaseBalanceBefore - baseProceeds
        );

        // Ensure that the base transfers were correct.

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

        IHyperdrive.Checkpoint memory checkpoint = hyperdrive.getCheckpoint(
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
        assertEq(poolInfoAfter.sharePrice, poolInfoBefore.sharePrice);
        assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
        assertEq(poolInfoAfter.longAverageMaturityTime, 0);
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
