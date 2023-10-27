// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import "forge-std/console2.sol";
import { stdError } from "forge-std/StdError.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils, IERC20, MockHyperdrive, MockHyperdriveDataProvider } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

uint256 constant TEN = 10e18;
uint256 constant ONE = 1e18;

contract OpenShortTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using Lib for *;
    using HyperdriveUtils for IHyperdrive;

    function setUp() public override {
        super.setUp();

        // Start recording event logs.
        vm.recordLogs();
    }

    function test_open_short_failure_zero_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to short zero bonds. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.MinimumTransactionAmount.selector);
        hyperdrive.openShort(
            0,
            type(uint256).max,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_open_short_failure_not_payable() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to open short. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.NotPayable.selector);
        hyperdrive.openShort{ value: 1 }(
            1,
            type(uint256).max,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_open_short_failure_pause() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to add zero base as liquidity. This should fail.
        vm.stopPrank();
        pause(true);
        vm.startPrank(bob);
        vm.expectRevert(IHyperdrive.Paused.selector);
        hyperdrive.openShort(
            0,
            type(uint256).max,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
        vm.stopPrank();
        pause(false);
    }

    function test_open_short_failure_extreme_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to short an extreme amount of bonds. This should fail.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 shortAmount = hyperdrive.getPoolInfo().shareReserves;
        baseToken.mint(shortAmount);
        baseToken.approve(address(hyperdrive), shortAmount);
        vm.expectRevert(IHyperdrive.InvalidTradeSize.selector);
        hyperdrive.openShort(
            shortAmount * 2,
            type(uint256).max,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_open_short_failure_minimum_share_price() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Attempt to open a long when the share price is lower than the minimum
        // share price.
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 bondAmount = 10e18;
        baseToken.mint(bondAmount);
        baseToken.approve(address(hyperdrive), bondAmount);
        uint256 minSharePrice = 2 * hyperdrive.getPoolInfo().sharePrice;
        vm.expectRevert(IHyperdrive.MinimumSharePrice.selector);
        hyperdrive.openShort(
            bondAmount,
            type(uint256).max,
            minSharePrice,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
    }

    function test_open_short() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the reserves before opening the short.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Short a small amount of bonds.
        uint256 shortAmount = 10e18;
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, shortAmount);

        // Verify the open short updates occurred correctly.
        verifyOpenShort(
            poolInfoBefore,
            contribution,
            basePaid,
            shortAmount,
            maturityTime,
            apr
        );
    }
    
    function logRateDelta(
        uint256 effectiveMarketRate,
        uint256 apr
    ) internal pure {
        uint256 rateDelta = effectiveMarketRate - apr;
        console2.log("rateDelta = %s", rateDelta.toString(18));
        uint256 rateDeltaAsPercent = rateDelta.divDown(apr);
        console2.log("  / starting_APR = %s", rateDeltaAsPercent.toString(18));
    }

    function testNumberTooBig() external {
        uint256 apr = 0.25e18;
        console2.log("starting APR = %s", apr.toString(18));

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);
        uint256 spotPrice = hyperdrive.calculateSpotPrice();
        console2.log("spot price   = %s", spotPrice.toString(18));

        // Get the reserves before opening the short.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Short a small amount of bonds.
        uint256 shortAmount = TEN.divDown(spotPrice);
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, shortAmount);

        // Market perspective
        console2.log("=== MARKET PERSPECTIVE ===");
        console2.log("bob sold   %s bonds to the LP", shortAmount.toString(18));
        uint256 effectiveExchangeRate = basePaid.divDown(shortAmount);
        uint256 effectiveMarketPrice = 1e18 - effectiveExchangeRate;
        console2.log("effectiveMarketPrice = %s", effectiveMarketPrice.toString(18));
        uint256 lp_portion = shortAmount.mulDown(effectiveMarketPrice);
        console2.log("  he gets %s base from the LP (shortAmount * effectiveMarketPrice)", lp_portion.toString(18));
        uint256 wallet_portion = shortAmount.mulDown(1e18 - effectiveMarketPrice);
        console2.log("  he adds  %s base from his wallet (shortAmount * (1-p))", wallet_portion.toString(18));
        uint256 total_portion = lp_portion + wallet_portion;
        console2.log("  both stay in the pool, to make the market solvent: %s + %s = %s", lp_portion.toString(18), wallet_portion.toString(18), total_portion.toString(18));
        uint256 effectiveMarketRate = (1e18 - effectiveMarketPrice).divDown(effectiveMarketPrice);
        console2.log("effectiveMarketRate  = %s", effectiveMarketRate.toString(18));
        logRateDelta(effectiveMarketRate, apr);

        // User perspective
        console2.log("=== USER PERSPECTIVE ===");
        console2.log("bob sold   %s bonds for %s base", shortAmount.toString(18), basePaid.toString(18));
        uint256 expectedBasePaid = shortAmount.mulDown(1e18 - spotPrice);
        console2.log("expectedBasePaid = %s (shortAmount * (1-p))", expectedBasePaid.toString(18));
        uint256 feePaid = basePaid - expectedBasePaid;
        console2.log("feePaid = %s", feePaid.toString(18));
        console2.log("  basePaid(%s) - expectedBasePaid(%s) = %s", basePaid.toString(18), expectedBasePaid.toString(18), feePaid.toString(18));
        uint256 feePaidAsPercent = feePaid.divDown(shortAmount);
        console2.log("  / shortAmount = %s", feePaidAsPercent.toString(18));
    }

    function test_open_short_with_small_amount() external {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        // Get the reserves before opening the short.
        IHyperdrive.PoolInfo memory poolInfoBefore = hyperdrive.getPoolInfo();

        // Short a small amount of bonds.
        uint256 shortAmount = .1e18;
        (uint256 maturityTime, uint256 basePaid) = openShort(bob, shortAmount);

        // Verify the open short updates occurred correctly.
        verifyOpenShort(
            poolInfoBefore,
            contribution,
            basePaid,
            shortAmount,
            maturityTime,
            apr
        );
    }

    function test_governance_fees_excluded_share_reserves() public {
        uint256 apr = 0.05e18;
        uint256 contribution = 500_000_000e18;

        // 1. Deploy a pool with zero fees
        IHyperdrive.PoolConfig memory config = testConfig(apr);
        deploy(address(deployer), config);
        // Initialize the pool with a large amount of capital.
        initialize(alice, apr, contribution);

        uint256 bondAmount = (hyperdrive.calculateMaxShort() * 90) / 100;
        // 2. Open a short
        openShort(bob, bondAmount);

        // 3. Record Share Reserves
        IHyperdrive.MarketState memory zeroFeeState = hyperdrive
            .getMarketState();

        // 4. deploy a pool with 100% curve fees and 100% gov fees (this is nice bc
        // it ensures that all the fees are credited to governance and thus subtracted
        // from the shareReserves
        config = testConfig(apr);
        config.fees = IHyperdrive.Fees({
            curve: 1e18,
            flat: 1e18,
            governance: 1e18
        });
        deploy(address(deployer), config);
        initialize(alice, apr, contribution);

        // 5. Open a Short
        bondAmount = (hyperdrive.calculateMaxShort() * 90) / 100;
        DepositOverrides memory depositOverrides = DepositOverrides({
            asBase: false,
            depositAmount: bondAmount * 2,
            minSharePrice: 0,
            minSlippage: 0,
            maxSlippage: type(uint128).max,
            extraData: new bytes(0)
        });
        openShort(bob, bondAmount, depositOverrides);

        // 6. Record Share Reserves
        IHyperdrive.MarketState memory maxFeeState = hyperdrive
            .getMarketState();

        // Since the fees are subtracted from reserves and accounted for
        // seperately, so this will be true
        assertEq(zeroFeeState.shareReserves, maxFeeState.shareReserves);

        uint256 govFees = hyperdrive.getUncollectedGovernanceFees();
        // Governance fees collected are non-zero
        assert(govFees > 1e5);

        // 7. deploy a pool with 100% curve fees and 0% gov fees
        config = testConfig(apr);
        config.fees = IHyperdrive.Fees({ curve: 1e18, flat: 0, governance: 0 });
        // Deploy and initialize the new pool
        deploy(address(deployer), config);
        initialize(alice, apr, contribution);

        // 8. Open a Short
        bondAmount = (hyperdrive.calculateMaxShort() * 90) / 100;
        openShort(bob, bondAmount);

        // 9. Record Share Reserves
        IHyperdrive.MarketState memory maxCurveFeeState = hyperdrive
            .getMarketState();

        // shareReserves should be greater here because there is no Gov being deducted
        assertGe(maxCurveFeeState.shareReserves, maxFeeState.shareReserves);
    }

    // TODO: This test addresses a specific failure case in calculating the
    // trader deposit. We should refactor the short calculation logic and fully
    // unit test this, which would remove the need for this test.
    function test_short_deposit_with_governance_fee() external {
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;

        // Alice initializes the pool. The pool has a curve fee of 100% and
        // governance fees of 0%.
        IHyperdrive.PoolConfig memory config = testConfig(fixedRate);
        config.fees.curve = 1e18;
        config.fees.governance = 0;
        deploy(address(deployer), config);
        initialize(alice, fixedRate, contribution);

        // Bob opens a short position.
        uint256 shortAmount = 100_000e18;
        (, uint256 basePaid) = openShort(bob, shortAmount);

        // Alice initializes the pool. The pool has a curve fee of 100% and
        // governance fees of 100%.
        config = testConfig(fixedRate);
        config.fees.curve = 1e18;
        config.fees.governance = 1e18;
        deploy(address(deployer), config);
        initialize(alice, fixedRate, contribution);

        // Bob opens a short position.
        (, uint256 basePaid2) = openShort(bob, shortAmount);

        // The governance fee shouldn't affect the short's deposit, so the base
        // paid should be the same in both cases.
        assertEq(basePaid, basePaid2);
    }

    function test_open_short_after_negative_interest(
        int256 variableRate
    ) external {
        // Alice initializes the pool.
        uint256 fixedRate = 0.05e18;
        uint256 contribution = 500_000_000e18;
        initialize(alice, fixedRate, contribution);

        // Get the deposit amount for a short opened with no negative interest.
        uint256 expectedBasePaid;
        uint256 snapshotId = vm.snapshot();
        uint256 shortAmount = 100_000e18;
        {
            hyperdrive.checkpoint(hyperdrive.latestCheckpoint());
            advanceTime(
                hyperdrive.getPoolConfig().checkpointDuration.mulDown(0.5e18),
                0
            );
            (, expectedBasePaid) = openShort(bob, shortAmount);
        }
        vm.revertTo(snapshotId);

        // Get the deposit amount for a short opened with negative interest.
        variableRate = variableRate.normalizeToRange(-100e18, 0);
        uint256 basePaid;
        {
            hyperdrive.checkpoint(hyperdrive.latestCheckpoint());
            advanceTime(
                hyperdrive.getPoolConfig().checkpointDuration.mulDown(0.5e18),
                variableRate
            );
            (, basePaid) = openShort(bob, shortAmount);
        }

        // The base paid should be greater than or equal (with a fudge factor)
        // to the base paid with no negative interest. In theory, we'd like the
        // deposits to be equal, but the trading calculation changes slightly
        // with negative interest due to rounding.
        assertGe(basePaid + 1e9, expectedBasePaid);
    }

    function verifyOpenShort(
        IHyperdrive.PoolInfo memory poolInfoBefore,
        uint256 contribution,
        uint256 basePaid,
        uint256 shortAmount,
        uint256 maturityTime,
        uint256 apr
    ) internal {
        // Ensure that one `OpenShort` event was emitted with the correct
        // arguments.
        {
            VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
                OpenShort.selector
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
                uint256 eventSharePrice,
                uint256 eventBondAmount
            ) = abi.decode(log.data, (uint256, uint256, uint256, uint256));
            assertEq(eventMaturityTime, maturityTime);
            assertEq(eventBaseAmount, basePaid);
            assertEq(eventSharePrice, hyperdrive.getPoolInfo().sharePrice);
            assertEq(eventBondAmount, shortAmount);
        }

        // Verify that Hyperdrive received the max loss and that Bob received
        // the short tokens.
        assertEq(
            baseToken.balanceOf(address(hyperdrive)),
            contribution + basePaid
        );
        assertEq(
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    maturityTime
                ),
                bob
            ),
            shortAmount
        );

        // Verify that the short didn't receive an APR higher than the pool's
        // APR.
        uint256 baseProceeds = shortAmount - basePaid;
        {
            uint256 realizedApr = HyperdriveUtils.calculateAPRFromRealizedPrice(
                baseProceeds,
                shortAmount,
                FixedPointMath.ONE_18
            );
            assertLt(apr, realizedApr);
        }

        // Verify that the reserves were updated correctly.
        IHyperdrive.PoolInfo memory poolInfoAfter = hyperdrive.getPoolInfo();

        {
            assertEq(
                poolInfoAfter.shareReserves,
                poolInfoBefore.shareReserves -
                    baseProceeds.divDown(poolInfoBefore.sharePrice)
            );
            assertEq(poolInfoAfter.sharePrice, poolInfoBefore.sharePrice);
            assertEq(
                poolInfoAfter.shareAdjustment,
                poolInfoBefore.shareAdjustment
            );
            assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
            assertEq(
                poolInfoAfter.longsOutstanding,
                poolInfoBefore.longsOutstanding
            );
            assertEq(poolInfoAfter.longAverageMaturityTime, 0);
            assertEq(
                poolInfoAfter.shortsOutstanding,
                poolInfoBefore.shortsOutstanding + shortAmount
            );
            assertApproxEqAbs(
                poolInfoAfter.shortAverageMaturityTime,
                maturityTime * 1e18,
                1
            );
        }

        // Ensure that the bond reserves were updated to have the correct APR.
        // Due to the way that the flat part of the trade is applied, the bond
        // reserve updates may not exactly correspond to the amount of bonds
        // transferred; however, the pool's APR should be identical to the APR
        // that the bond amount transfer implies.
        assertApproxEqAbs(
            HyperdriveUtils.calculateSpotAPR(hyperdrive),
            HyperdriveMath.calculateSpotAPR(
                poolInfoAfter.shareReserves,
                poolInfoBefore.bondReserves + shortAmount,
                INITIAL_SHARE_PRICE,
                POSITION_DURATION,
                hyperdrive.getPoolConfig().timeStretch
            ),
            5
        );
    }
}
