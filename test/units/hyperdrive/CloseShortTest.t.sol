// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdError } from "forge-std/StdError.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { YieldSpaceMath } from "../../../contracts/src/libraries/YieldSpaceMath.sol";
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
        // Initialize the pool with a large amount of capital.
        uint256 apr = 0.05e18;
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

    function test_close_short_failure_destination_zero_address() external {
        // Initialize the pool with a large amount of capital.
        uint256 apr = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a short.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, ) = openShort(bob, bondAmount);

        // Bob attempts to set the destination to the zero address.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.RestrictedZeroAddress.selector);
        hyperdrive.closeShort(
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

    function test_close_short_failure_invalid_amount() external {
        // Initialize the pool with a large amount of capital.
        uint256 apr = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Open a short.
        uint256 bondAmount = 10e18;
        (uint256 maturityTime, ) = openShort(bob, bondAmount);

        // Attempt to close too many shorts. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.InsufficientBalance.selector);
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
        // Initialize the pool with a large amount of capital.
        uint256 apr = 0.05e18;
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

    function test_close_short_failure_output_limit() external {
        // Initialize the pool with a large amount of capital.
        uint256 apr = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Bob opens a short.
        uint256 shortAmount = 10_000e18;
        (uint256 maturityTime, uint256 shortBasePaid) = openShort(
            bob,
            shortAmount
        );

        // Bob tries to close his short with an output limit that is too high.
        // This should fail the output limit check.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.OutputLimit.selector);
        hyperdrive.closeShort(
            maturityTime,
            shortAmount,
            shortBasePaid.mulDown(1.1e18),
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
        vm.expectRevert(IHyperdrive.InsufficientLiquidity.selector);
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
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive), 0);

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
        hyperdrive.checkpoint(HyperdriveUtils.latestCheckpoint(hyperdrive), 0);
        uint256 closeVaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;

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
                closeVaultSharePrice -
                    hyperdrive.getPoolConfig().initialVaultSharePrice,
                hyperdrive.getPoolConfig().initialVaultSharePrice
            )
            .divDown(closeVaultSharePrice)
            .mulDown(hyperdrive.getPoolInfo().vaultSharePrice);
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
                destination: bob,
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
                destination: bob,
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
                destination: bob,
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
                destination: bob,
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
            // Initialize the pool with enough capital for the effective share
            // reserves to exceed the minimum share reserves.
            deploy(bob, 0.035e18, 1e18, 0, 0, 0, 0);
            initialize(bob, 0.035e18, 5 * MINIMUM_SHARE_RESERVES);

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
            // Initialize the pool with enough capital for the effective share
            // reserves to exceed the minimum share reserves.
            deploy(bob, 0.035e18, 1e18, 0, 0, 0, 0);
            initialize(bob, 0.035e18, 5 * MINIMUM_SHARE_RESERVES);

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
            // Initialize the pool with enough capital for the effective share
            // reserves to exceed the minimum share reserves.
            deploy(bob, 0.035e18, 1e18, 0, 0, 0, 0);
            initialize(bob, 0.035e18, 5 * MINIMUM_SHARE_RESERVES);

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
            // Initialize the pool with enough capital for the effective share
            // reserves to exceed the minimum share reserves.
            deploy(bob, 0.035e18, 1e18, 0, 0, 0, 0);
            initialize(bob, 0.035e18, 5 * MINIMUM_SHARE_RESERVES);

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
        assertApproxEqAbs(shortProceeds1, shortProceeds2, 106 wei);
        assertApproxEqAbs(shortProceeds1, shortProceeds3, 9.8e9);

        // NOTE: This is a large tolerance, but it is explained in issue #691.
        assertApproxEqAbs(shortProceeds1, shortProceeds4, 5.3e18);
        assertGe(shortProceeds1, shortProceeds4);
    }

    function test_close_short_destination() external {
        // Initialize the pool with a large amount of capital.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Bob opens a short.
        uint256 shortAmount = 1_000_000e18;
        (uint256 maturityTime, ) = openShort(bob, shortAmount);

        // Get the pool info before closing the short.
        IHyperdrive.PoolInfo memory poolInfo = hyperdrive.getPoolInfo();

        // Bob closes his short and sends the proceeds to Celine.
        uint256 baseProceeds = closeShort(
            bob,
            maturityTime,
            shortAmount,
            WithdrawalOverrides({
                asBase: true,
                destination: celine,
                minSlippage: 0,
                extraData: new bytes(0)
            })
        );

        // Ensure that the correct event was emitted.
        (uint256 shareReservesDelta, ) = expectedCalculateCloseShort(
            maturityTime,
            shortAmount,
            poolInfo,
            hyperdrive.getPoolInfo()
        );
        verifyCloseShortEvent(
            bob,
            celine,
            maturityTime,
            shortAmount,
            baseProceeds,
            shareReservesDelta.mulDown(hyperdrive.getPoolInfo().vaultSharePrice)
        );

        // Ensure that the proceeds were sent to Celine.
        assertEq(baseToken.balanceOf(bob), 0);
        assertEq(baseToken.balanceOf(celine), baseProceeds);
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
        // Retrieve the pool info after the trade.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();

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

        // Calculate the expected share reseres delta and share adjustment delta.
        (
            uint256 shareReservesDelta,
            uint256 shareAdjustmentDelta
        ) = expectedCalculateCloseShort(
                testCase.maturityTime,
                testCase.bondAmount,
                testCase.poolInfoBefore,
                poolInfoAfter
            );

        // Ensure that one `CloseShort` event was emitted with the correct
        // arguments.
        verifyCloseShortEvent(
            bob,
            bob,
            testCase.maturityTime,
            testCase.bondAmount,
            testCase.baseProceeds,
            shareReservesDelta.mulDown(testCase.poolInfoBefore.vaultSharePrice)
        );

        // Verify that the other state was updated correctly.
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
            uint256 initialVaultSharePrice = hyperdrive
                .getPoolConfig()
                .initialVaultSharePrice;
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

    function verifyCloseShortEvent(
        address trader,
        address destination,
        uint256 maturityTime,
        uint256 bondAmount,
        uint256 baseProceeds,
        uint256 basePayment
    ) internal {
        // Ensure that one `CloseShort` event was emitted with the correct
        // arguments.
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            CloseShort.selector
        );
        assertEq(logs.length, 1);
        VmSafe.Log memory log = logs[0];
        assertEq(address(uint160(uint256(log.topics[1]))), trader);
        assertEq(address(uint160(uint256(log.topics[2]))), destination);
        assertEq(
            uint256(log.topics[3]),
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, maturityTime)
        );
        (
            uint256 eventMaturityTime,
            uint256 eventAmount,
            uint256 eventVaultSharePrice,
            bool eventAsBase,
            uint256 eventBasePayment,
            uint256 eventBondAmount
        ) = abi.decode(
                log.data,
                (uint256, uint256, uint256, bool, uint256, uint256)
            );
        assertEq(eventMaturityTime, maturityTime);
        assertEq(eventAmount, baseProceeds);
        assertEq(
            eventVaultSharePrice,
            hyperdrive.getPoolInfo().vaultSharePrice
        );
        assertEq(eventAsBase, true);
        assertEq(eventBasePayment, basePayment);
        assertEq(eventBondAmount, bondAmount);
    }

    function expectedCalculateCloseShort(
        uint256 maturityTime,
        uint256 bondAmount,
        IHyperdrive.PoolInfo memory poolInfoBefore,
        IHyperdrive.PoolInfo memory poolInfoAfter
    )
        internal
        view
        returns (uint256 shareReservesDelta, uint256 shareAdjustmentDelta)
    {
        uint256 timeRemaining = hyperdrive.calculateTimeRemaining(maturityTime);
        (, , shareReservesDelta) = HyperdriveMath.calculateCloseShort(
            HyperdriveMath.calculateEffectiveShareReserves(
                poolInfoBefore.shareReserves,
                poolInfoBefore.shareAdjustment
            ),
            poolInfoBefore.bondReserves,
            bondAmount,
            timeRemaining,
            hyperdrive.getPoolConfig().timeStretch,
            poolInfoBefore.vaultSharePrice,
            hyperdrive.getPoolConfig().initialVaultSharePrice
        );
        uint256 timeElapsed = ONE - timeRemaining;
        shareAdjustmentDelta = bondAmount.mulDivDown(
            timeElapsed,
            poolInfoAfter.vaultSharePrice
        );
        uint256 initialVaultSharePrice = hyperdrive
            .getPoolConfig()
            .initialVaultSharePrice;
        uint256 closeVaultSharePrice = block.timestamp < maturityTime
            ? hyperdrive.getPoolInfo().vaultSharePrice
            : hyperdrive.getCheckpoint(maturityTime).vaultSharePrice;
        if (
            closeVaultSharePrice <
            hyperdrive.getPoolConfig().initialVaultSharePrice
        ) {
            shareReservesDelta = shareReservesDelta.mulDivDown(
                closeVaultSharePrice,
                initialVaultSharePrice
            );
            shareAdjustmentDelta = shareAdjustmentDelta.mulDivDown(
                closeVaultSharePrice,
                initialVaultSharePrice
            );
        }

        return (shareReservesDelta, shareAdjustmentDelta);
    }
}
