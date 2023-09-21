// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { stdError } from "forge-std/StdError.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveTest, HyperdriveUtils, IERC20, MockHyperdrive, MockHyperdriveDataProvider } from "../../utils/HyperdriveTest.sol";
import { Lib } from "../../utils/Lib.sol";

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
        hyperdrive.openShort(0, type(uint256).max, bob, true);
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
        hyperdrive.openShort{ value: 1 }(1, type(uint256).max, bob, true);
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
        hyperdrive.openShort(0, type(uint256).max, bob, true);
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
        hyperdrive.openShort(shortAmount * 2, type(uint256).max, bob, true);
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

    function test_RevertsWithNegativeInterestRate() public {
        uint256 apr = 0.05e18;

        // Initialize the pool with a large amount of capital.
        uint256 contribution = 500_000_000e18;
        initialize(alice, apr, contribution);

        vm.stopPrank();
        vm.startPrank(bob);

        uint256 bondAmount = (hyperdrive.calculateMaxShort() * 90) / 100;
        openShort(bob, bondAmount);

        uint256 longAmount = (hyperdrive.calculateMaxLong() * 50) / 100;
        openLong(bob, longAmount);

        //vm.expectRevert(IHyperdrive.NegativeInterest.selector);

        uint256 baseAmount = (hyperdrive.calculateMaxShort() * 100) / 100;
        openShort(bob, baseAmount);
        //I think we could trigger this with big short, open long, and short?
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
            asUnderlying: false,
            depositAmount: bondAmount * 2,
            minSlippage: 0,
            maxSlippage: type(uint128).max
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
                uint256 eventBondAmount
            ) = abi.decode(log.data, (uint256, uint256, uint256));
            assertEq(eventMaturityTime, maturityTime);
            assertEq(eventBaseAmount, basePaid);
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
            assertEq(poolInfoAfter.lpTotalSupply, poolInfoBefore.lpTotalSupply);
            assertEq(poolInfoAfter.sharePrice, poolInfoBefore.sharePrice);
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
            HyperdriveUtils.calculateAPRFromReserves(hyperdrive),
            HyperdriveMath.calculateAPRFromReserves(
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
