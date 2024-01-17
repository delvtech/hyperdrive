// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { stdError } from "forge-std/StdError.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "contracts/src/libraries/YieldSpaceMath.sol";
import { HyperdriveTest, HyperdriveUtils } from "test/utils/HyperdriveTest.sol";
import { Lib } from "test/utils/Lib.sol";

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
        vm.expectRevert(IHyperdrive.MinimumTransactionAmount.selector);
        hyperdrive.closeShort(
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
        hyperdrive.closeShort(
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
        hyperdrive.closeShort(
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
            MINIMUM_TRANSACTION_AMOUNT,
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
            MINIMUM_TRANSACTION_AMOUNT,
            initialShortAmount
        );
        vm.expectRevert(IHyperdrive.NegativeInterest.selector);
        hyperdrive.closeShort(
            maturityTime,
            finalShortAmount,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
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
            TestCase({
                poolInfoBefore: poolInfoBefore,
                bobBaseBalanceBefore: bobBaseBalanceBefore,
                hyperdriveBaseBalanceBefore: hyperdriveBaseBalanceBefore,
                baseProceeds: baseProceeds,
                bondAmount: bondAmount,
                maturityTime: maturityTime,
                wasCheckpointed: false
            })
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
            TestCase({
                poolInfoBefore: poolInfoBefore,
                bobBaseBalanceBefore: bobBaseBalanceBefore,
                hyperdriveBaseBalanceBefore: hyperdriveBaseBalanceBefore,
                baseProceeds: baseProceeds,
                bondAmount: bondAmount,
                maturityTime: maturityTime,
                wasCheckpointed: false
            })
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
            TestCase({
                poolInfoBefore: poolInfoBefore,
                bobBaseBalanceBefore: bobBaseBalanceBefore,
                hyperdriveBaseBalanceBefore: hyperdriveBaseBalanceBefore,
                baseProceeds: baseProceeds,
                bondAmount: bondAmount,
                maturityTime: maturityTime,
                wasCheckpointed: false
            })
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
            TestCase({
                poolInfoBefore: poolInfoBefore,
                bobBaseBalanceBefore: bobBaseBalanceBefore,
                hyperdriveBaseBalanceBefore: hyperdriveBaseBalanceBefore,
                baseProceeds: baseProceeds,
                bondAmount: bondAmount,
                maturityTime: maturityTime,
                wasCheckpointed: false
            })
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
            TestCase({
                poolInfoBefore: poolInfoBefore,
                bobBaseBalanceBefore: bobBaseBalanceBefore,
                hyperdriveBaseBalanceBefore: hyperdriveBaseBalanceBefore,
                baseProceeds: baseProceeds,
                bondAmount: bondAmount,
                maturityTime: maturityTime,
                wasCheckpointed: false
            })
        );
    }

    function test_close_short_negative_interest_before_maturity() external {
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
            TestCase({
                poolInfoBefore: poolInfoBefore,
                bobBaseBalanceBefore: bobBaseBalanceBefore,
                hyperdriveBaseBalanceBefore: hyperdriveBaseBalanceBefore,
                baseProceeds: baseProceeds,
                bondAmount: bondAmount,
                maturityTime: maturityTime,
                wasCheckpointed: true
            })
        );
    }

    function test_close_short_negative_interest_after_maturity() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Short some bonds.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, ) = openShort(bob, bondAmount);

        // The term passes and shares lose value
        advanceTime(POSITION_DURATION, 0.5e18);

        // A checkpoint is created to lock in the close price.
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive));
        uint256 closeSharePrice = hyperdrive.getPoolInfo().sharePrice;

        // Another term passes and positive interest accrues.
        advanceTime(POSITION_DURATION, -0.2e18);

        // Get the reserves and account balances before closing the short.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 hyperdriveBaseBalanceBefore = baseToken.balanceOf(
            address(hyperdrive)
        );

        // Redeem the bonds.
        uint256 baseProceeds = closeShort(bob, maturityTime, bondAmount);

        // Verify that Bob receives a haircut on variable interest earned while
        // the short was open.
        uint256 expectedProceeds = bondAmount
            .mulDivDown(
                closeSharePrice - hyperdrive.getPoolConfig().initialSharePrice,
                hyperdrive.getPoolConfig().initialSharePrice
            )
            .divDown(closeSharePrice)
            .mulDown(hyperdrive.getPoolInfo().sharePrice);
        assertApproxEqAbs(baseProceeds, expectedProceeds, 5);

        // Verify that the close long updates were correct.
        verifyCloseShort(
            TestCase({
                poolInfoBefore: poolInfoBefore,
                bobBaseBalanceBefore: bobBaseBalanceBefore,
                hyperdriveBaseBalanceBefore: hyperdriveBaseBalanceBefore,
                baseProceeds: baseProceeds,
                bondAmount: bondAmount,
                maturityTime: maturityTime,
                wasCheckpointed: true
            })
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
            (basePaid - baseProceeds).divDown(basePaid),
            1e18,
            1e15 // TODO Large tolerance?
        );

        // Verify that the close short updates were correct.
        verifyCloseShort(
            TestCase({
                poolInfoBefore: poolInfoBefore,
                bobBaseBalanceBefore: bobBaseBalanceBefore,
                hyperdriveBaseBalanceBefore: hyperdriveBaseBalanceBefore,
                baseProceeds: baseProceeds,
                bondAmount: bondAmount,
                maturityTime: maturityTime,
                wasCheckpointed: false
            })
        );
    }

    function test_short_fees_collect_on_close_at_maturity() external {
        uint256 fixedRate = 0.05e18;
        int256 variableRate = -0.05e18;
        uint256 contribution = 500_000_000e18;

        // 1. Deploy a pool with zero fees
        IHyperdrive.PoolConfig memory config = testConfig(
            fixedRate,
            POSITION_DURATION
        );
        deploy(address(deployer), config);
        // Initialize the pool with a large amount of capital.
        initialize(alice, fixedRate, contribution);

        // 2. A short is opened and the term passes. The long is closed at maturity.
        (uint256 maturityTime, uint256 baseAmount) = openShort(bob, 10e18);
        advanceTime(POSITION_DURATION, variableRate);
        closeShort(bob, maturityTime, baseAmount);

        // 3. Record Share Reserves
        IHyperdrive.MarketState memory zeroFeeState = hyperdrive
            .getMarketState();

        // 4. deploy a pool with 100% curve fees and 100% gov fees (this is nice bc
        // it ensures that all the fees are credited to governance and thus subtracted
        // from the shareReserves
        config = testConfig(fixedRate, POSITION_DURATION);
        config.fees = IHyperdrive.Fees({
            curve: 0,
            flat: 1e18,
            governanceLP: 1e18,
            governanceZombie: 1e18
        });
        deploy(address(deployer), config);
        initialize(alice, fixedRate, contribution);

        // 5. Open and close a short at maturity, advancing the time
        (maturityTime, baseAmount) = openShort(
            bob,
            10e18,
            DepositOverrides({
                asBase: false,
                // NOTE: Roughly double deposit amount needed to cover 100% flat fee
                depositAmount: 10e18 * 2,
                minSharePrice: 0,
                minSlippage: 0,
                maxSlippage: type(uint128).max,
                extraData: new bytes(0)
            })
        );
        advanceTime(POSITION_DURATION, variableRate);
        closeShort(bob, maturityTime, baseAmount - 10e18); // Account for flatFee
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
            flat: 1e18,
            governanceLP: 0,
            governanceZombie: 0
        });
        // Deploy and initialize the new pool
        deploy(address(deployer), config);
        initialize(alice, fixedRate, contribution);

        // 8. Open and close another short at maturity as well, advancing the time
        (maturityTime, baseAmount) = openShort(
            bob,
            10e18,
            DepositOverrides({
                asBase: false,
                // NOTE: Roughly double deposit amount needed to cover 100% flat fee
                depositAmount: 10e18 * 2,
                minSharePrice: 0,
                minSlippage: 0,
                maxSlippage: type(uint128).max,
                extraData: new bytes(0)
            })
        );
        advanceTime(POSITION_DURATION, variableRate);
        closeShort(bob, maturityTime, baseAmount - 10e18);

        // 9. Record Share Reserves
        IHyperdrive.MarketState memory maxFlatFeeState = hyperdrive
            .getMarketState();

        // Since the fees are subtracted from reserves and accounted for
        // seperately, this will be true
        assertEq(zeroFeeState.shareReserves, maxFeeState.shareReserves);
        assertGt(maxFlatFeeState.shareReserves, maxFeeState.shareReserves);
    }

    function test_governance_fees_collected_at_maturity() external {
        uint256 fixedRate = 0.05e18;
        int256 variableRate = -0.05e18;
        uint256 contribution = 500_000_000e18;
        uint256 maturityTime;

        // Initialize a pool with no flat fee as a baseline
        IHyperdrive.PoolConfig memory config = testConfig(
            fixedRate,
            POSITION_DURATION
        );
        config.fees = IHyperdrive.Fees({
            curve: 0,
            flat: 0,
            governanceLP: 0,
            governanceZombie: 0
        });
        deploy(address(deployer), config);
        initialize(alice, fixedRate, contribution);

        // Open a short and note the deposit paid
        uint256 deposit0;
        (maturityTime, deposit0) = openShort(
            bob,
            10e18,
            DepositOverrides({
                asBase: false,
                // NOTE: Roughly double deposit amount needed to cover 100% flat fee
                depositAmount: 10e18 * 2,
                minSharePrice: 0,
                minSlippage: 0,
                maxSlippage: type(uint128).max,
                extraData: new bytes(0)
            })
        );
        advanceTime(POSITION_DURATION, variableRate);

        // Close the short with yield, so flat fee is fully paid
        closeShort(bob, maturityTime, deposit0);

        // Record Share Reserves
        IHyperdrive.MarketState memory noFlatFee = hyperdrive.getMarketState();

        // Configure a pool with a 100% flatFee
        config = testConfig(fixedRate, POSITION_DURATION);
        config.fees = IHyperdrive.Fees({
            curve: 0,
            flat: 1e18,
            governanceLP: 0,
            governanceZombie: 0
        });
        // Deploy and initialize the new pool
        deploy(address(deployer), config);
        initialize(alice, fixedRate, contribution);

        // Open a short and note the deposit
        uint256 deposit1;
        (maturityTime, deposit1) = openShort(
            bob,
            10e18,
            DepositOverrides({
                asBase: false,
                // NOTE: Roughly double deposit amount needed to cover 100% flat fee
                depositAmount: 10e18 * 2,
                minSharePrice: 0,
                minSlippage: 0,
                maxSlippage: type(uint128).max,
                extraData: new bytes(0)
            })
        );
        advanceTime(POSITION_DURATION, variableRate);

        // Close the short with yield, so flat fee is fully paid
        closeShort(bob, maturityTime, deposit1 - 10e18);

        IHyperdrive.MarketState memory maxFlatFeeState = hyperdrive
            .getMarketState();

        // deposit0 should be lower as it does not have a 100% flatFee added on top
        assertLt(deposit0, deposit1);
        // Share reserves should be greater in the max fee state for accruing more in fees
        assertGt(maxFlatFeeState.shareReserves, noFlatFee.shareReserves);
    }

    function test_close_short_compare_late_redemptions() external {
        int256 variableRate = 2e18;
        uint256 shortTradeSize = 1_000_000e18;
        uint256 shortProceeds1;
        {
            // Initialize the pool with capital.
            deploy(bob, 0.035e18, 1e18, 0, 0, 0, 0);
            initialize(bob, 0.035e18, 2 * MINIMUM_SHARE_RESERVES);

            // Alice adds liquidity.
            uint256 initialLiquidity = 500_000_000e18;
            addLiquidity(alice, initialLiquidity);

            // Celine opens a short.
            (uint256 maturityTime, ) = openShort(celine, shortTradeSize);

            // Term passes with interest.
            advanceTimeWithCheckpoints2(POSITION_DURATION, variableRate);

            // Celina redeems her short on time.
            shortProceeds1 = closeShort(celine, maturityTime, shortTradeSize);
        }

        uint256 shortProceeds2;
        {
            // Initialize the pool with capital.
            deploy(bob, 0.035e18, 1e18, 0, 0, 0, 0);
            initialize(bob, 0.035e18, 2 * MINIMUM_SHARE_RESERVES);

            // Alice adds liquidity.
            uint256 initialLiquidity = 500_000_000e18;
            addLiquidity(alice, initialLiquidity);

            // Celine opens a short.
            (uint256 maturityTime, ) = openShort(celine, shortTradeSize);

            // Term passes with interest.
            advanceTimeWithCheckpoints2(POSITION_DURATION, variableRate);

            // Time passes with interest.
            advanceTimeWithCheckpoints2(POSITION_DURATION, variableRate);

            // Celina redeems her short late.
            shortProceeds2 = closeShort(celine, maturityTime, shortTradeSize);
        }

        uint256 shortProceeds3;
        {
            // Initialize the pool with capital.
            deploy(bob, 0.035e18, 1e18, 0, 0, 0, 0);
            initialize(bob, 0.035e18, 2 * MINIMUM_SHARE_RESERVES);

            // Alice adds liquidity.
            uint256 initialLiquidity = 500_000_000e18;
            addLiquidity(alice, initialLiquidity);

            // Celine opens a short.
            (uint256 maturityTime, ) = openShort(celine, shortTradeSize);

            // Term passes with interest.
            advanceTimeWithCheckpoints2(POSITION_DURATION, variableRate);

            // Time passes with interest.
            advanceTimeWithCheckpoints2(POSITION_DURATION * 10, variableRate);

            // Celina redeems her short late.
            shortProceeds3 = closeShort(celine, maturityTime, shortTradeSize);
        }

        uint256 shortProceeds4;
        {
            // Initialize the pool with capital.
            deploy(bob, 0.035e18, 1e18, 0, 0, 0, 0);
            initialize(bob, 0.035e18, 2 * MINIMUM_SHARE_RESERVES);

            // Alice adds liquidity.
            uint256 initialLiquidity = 500_000_000e18;
            addLiquidity(alice, initialLiquidity);

            // Celine opens a short.
            (uint256 maturityTime, ) = openShort(celine, shortTradeSize);

            // Term passes with interest.
            advanceTimeWithCheckpoints2(POSITION_DURATION, variableRate);

            // Time passes with interest.
            advanceTimeWithCheckpoints2(POSITION_DURATION * 20, variableRate);

            // Celina redeems her short late.
            shortProceeds4 = closeShort(celine, maturityTime, shortTradeSize);
        }

        // Verify that the proceeds are about the same.
        assertApproxEqAbs(shortProceeds1, shortProceeds2, 60 wei);
        assertApproxEqAbs(shortProceeds1, shortProceeds3, 6.2e9);

        // NOTE: This is a large tolerance, but it is explained in issue #691.
        assertApproxEqAbs(shortProceeds1, shortProceeds4, 3.6e18);
        assertGe(shortProceeds1, shortProceeds4);
    }

    struct TestCase {
        IHyperdrive.PoolInfo poolInfoBefore;
        uint256 bobBaseBalanceBefore;
        uint256 hyperdriveBaseBalanceBefore;
        uint256 baseProceeds;
        uint256 bondAmount;
        uint256 maturityTime;
        bool wasCheckpointed;
    }

    function verifyCloseShort(TestCase memory testCase) internal {
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
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    testCase.maturityTime
                )
            );
            (
                uint256 eventMaturityTime,
                uint256 eventBaseAmount,
                uint256 eventSharePrice,
                uint256 eventBondAmount
            ) = abi.decode(log.data, (uint256, uint256, uint256, uint256));
            assertEq(eventMaturityTime, testCase.maturityTime);
            assertEq(eventBaseAmount, testCase.baseProceeds);
            assertEq(eventSharePrice, hyperdrive.getPoolInfo().sharePrice);
            assertEq(eventBondAmount, testCase.bondAmount);
        }

        // Ensure that the correct amount of base was transferred from
        // Hyperdrive to Bob.
        assertEq(
            baseToken.balanceOf(bob),
            testCase.bobBaseBalanceBefore + testCase.baseProceeds
        );
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            testCase.hyperdriveBaseBalanceBefore - testCase.baseProceeds
        );

        // Verify that all of Bob's shorts were burned.
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    testCase.maturityTime
                ),
                bob
            ),
            0
        );

        // Retrieve the pool info after the trade.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();

        // Verify that the other state was updated correctly.
        uint256 timeRemaining = HyperdriveUtils.calculateTimeRemaining(
            hyperdrive,
            testCase.maturityTime
        );
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
                poolInfoAfter.shortsOutstanding,
                testCase.poolInfoBefore.shortsOutstanding
            );
        } else {
            // TODO: Re-evaluate this. This is obviously correct; however, it may
            // be better to use HyperdriveMath or find an approximation so that we
            // aren't repeating ourselves.
            uint256 shareReservesDelta = testCase.bondAmount.mulDivDown(
                ONE - timeRemaining,
                testCase.poolInfoBefore.sharePrice
            ) +
                YieldSpaceMath.calculateSharesInGivenBondsOutUp(
                    testCase.poolInfoBefore.shareReserves,
                    testCase.poolInfoBefore.bondReserves,
                    testCase.bondAmount.mulDown(timeRemaining),
                    ONE - hyperdrive.getPoolConfig().timeStretch,
                    testCase.poolInfoBefore.sharePrice,
                    hyperdrive.getPoolConfig().initialSharePrice
                );
            uint256 timeElapsed = ONE -
                hyperdrive.calculateTimeRemaining(testCase.maturityTime);
            uint256 shareAdjustmentDelta = testCase.bondAmount.mulDivDown(
                timeElapsed,
                poolInfoAfter.sharePrice
            );
            uint256 initialSharePrice = hyperdrive
                .getPoolConfig()
                .initialSharePrice;
            if (
                poolInfoAfter.sharePrice <
                hyperdrive.getPoolConfig().initialSharePrice
            ) {
                shareReservesDelta = shareReservesDelta.mulDivDown(
                    poolInfoAfter.sharePrice,
                    initialSharePrice
                );
                shareAdjustmentDelta = shareAdjustmentDelta.mulDivDown(
                    poolInfoAfter.sharePrice,
                    initialSharePrice
                );
            }
            assertApproxEqAbs(
                poolInfoAfter.shareReserves,
                testCase.poolInfoBefore.shareReserves + shareReservesDelta,
                1e10
            );

            // There are two components of the share adjustment delta. The first
            // is from negative interest and the second is from the flat update.
            // Without re-doing the calculation here, we can check that the
            // share adjustment delta is greater than or equal to the flat update
            // and verify that k remained invariant.
            assertLe(
                poolInfoAfter.shareAdjustment,
                testCase.poolInfoBefore.shareAdjustment +
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
                    poolInfoAfter.sharePrice,
                    initialSharePrice
                ),
                YieldSpaceMath.kDown(
                    HyperdriveMath.calculateEffectiveShareReserves(
                        testCase.poolInfoBefore.shareReserves,
                        testCase.poolInfoBefore.shareAdjustment
                    ),
                    testCase.poolInfoBefore.bondReserves,
                    ONE - hyperdrive.getPoolConfig().timeStretch,
                    testCase.poolInfoBefore.sharePrice,
                    initialSharePrice
                ),
                1e10
            );
            assertEq(
                poolInfoAfter.shortsOutstanding,
                testCase.poolInfoBefore.shortsOutstanding - testCase.bondAmount
            );
        }
        assertEq(
            poolInfoAfter.lpTotalSupply,
            testCase.poolInfoBefore.lpTotalSupply
        );
        assertEq(
            poolInfoAfter.longsOutstanding,
            testCase.poolInfoBefore.longsOutstanding
        );
        assertEq(poolInfoAfter.longAverageMaturityTime, 0);
        assertEq(poolInfoAfter.shortAverageMaturityTime, 0);
    }
}
