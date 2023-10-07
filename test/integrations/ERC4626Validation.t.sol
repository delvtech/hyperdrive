// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC4626HyperdriveDeployer } from "contracts/src/factory/ERC4626HyperdriveDeployer.sol";
import { ERC4626HyperdriveFactory } from "contracts/src/factory/ERC4626HyperdriveFactory.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "contracts/src/interfaces/IERC4626.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { MockERC4626Hyperdrive } from "../mocks/Mock4626Hyperdrive.sol";
import { HyperdriveTest } from "../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../utils/HyperdriveUtils.sol";
import { Lib } from "../utils/Lib.sol";

abstract contract ERC4626ValidationTest is HyperdriveTest {
    using FixedPointMath for *;
    using Lib for *;

    ERC4626HyperdriveFactory internal factory;
    IERC20 internal underlyingToken;
    IERC4626 internal token;
    MockERC4626Hyperdrive hyperdriveInstance;

    uint256 internal constant FIXED_RATE = 0.05e18;

    function _setUp() internal {
        super.setUp();

        vm.startPrank(deployer);

        // Initialize deployer contracts and forwarder
        ERC4626HyperdriveDeployer simpleDeployer = new ERC4626HyperdriveDeployer(
                token
            );
        address[] memory defaults = new address[](1);
        defaults[0] = bob;
        forwarderFactory = new ForwarderFactory();

        // Hyperdrive factory to produce ERC4626 instances for stethERC4626
        factory = new ERC4626HyperdriveFactory(
            HyperdriveFactory.FactoryConfig(
                alice,
                bob,
                bob,
                IHyperdrive.Fees(0, 0, 0),
                IHyperdrive.Fees(1e18, 1e18, 1e18),
                defaults
            ),
            simpleDeployer,
            address(forwarderFactory),
            forwarderFactory.ERC20LINK_HASH(),
            token,
            new address[](0)
        );

        // Config changes required to support ERC4626 with the correct initial Share Price
        IHyperdrive.PoolConfig memory config = testConfig(FIXED_RATE);
        config.baseToken = underlyingToken;
        config.initialSharePrice = token.convertToAssets(FixedPointMath.ONE_18);
        uint256 contribution = 7_500e18;
        vm.stopPrank();
        vm.startPrank(alice);

        // Set approval to allow initial contribution to factory
        underlyingToken.approve(address(factory), type(uint256).max);

        // Deploy and set hyperdrive instance
        hyperdrive = factory.deployAndInitialize(
            config,
            new bytes32[](0),
            contribution,
            FIXED_RATE
        );

        // Setup maximum approvals so transfers don't require further approval
        underlyingToken.approve(address(hyperdrive), type(uint256).max);
        underlyingToken.approve(address(token), type(uint256).max);
        token.approve(address(hyperdrive), type(uint256).max);
        vm.stopPrank();

        // Start recording events.
        vm.recordLogs();
    }

    function advanceTimeWithYield(uint256 timeDelta) public virtual;

    function test_deployAndInitialize() external {
        vm.startPrank(alice);

        IHyperdrive.PoolConfig memory config = testConfig(FIXED_RATE);
        // Required to support ERC4626, since the test config initialSharePrice is wrong
        config.baseToken = underlyingToken;
        // Designed to ensure compatibility ../../contracts/src/instances/ERC4626Hyperdrive.sol#L122C1-L122C1
        config.initialSharePrice = token.convertToAssets(FixedPointMath.ONE_18);

        uint256 contribution = 10_000e18;

        underlyingToken.approve(address(factory), type(uint256).max);

        // Deploy a new hyperdrive instance
        hyperdrive = factory.deployAndInitialize(
            config,
            new bytes32[](0),
            contribution,
            FIXED_RATE
        );

        // Ensure minimumShareReserves were added, and lpTotalSupply increased
        assertEq(
            hyperdrive.getPoolInfo().lpTotalSupply,
            hyperdrive.getPoolInfo().shareReserves - config.minimumShareReserves
        );

        // Verify that the correct events were emitted during creation
        verifyFactoryEvents(
            factory,
            alice,
            contribution,
            FIXED_RATE,
            config.minimumShareReserves,
            new bytes32[](0),
            1e5
        );
    }

    function test_OpenLongWithUnderlying(uint256 basePaid) external {
        // Establish baseline variables
        uint256 totalPooledAssetsBefore = token.totalAssets();
        uint256 totalSharesBefore = token.convertToShares(
            totalPooledAssetsBefore
        );
        AccountBalances memory aliceBalancesBefore = getAccountBalances(alice);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        vm.startPrank(alice);

        basePaid = basePaid.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            HyperdriveUtils.calculateMaxLong(hyperdrive).min(
                underlyingToken.balanceOf(alice)
            )
        );

        // Open a long with underlying tokens
        openLongERC4626(alice, basePaid, true);

        // Verify balances correctly updated
        verifyDepositUnderlying(
            alice,
            basePaid,
            totalPooledAssetsBefore,
            totalSharesBefore,
            aliceBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_OpenLongWithShares(uint256 basePaid) external {
        vm.startPrank(alice);
        basePaid = basePaid.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            HyperdriveUtils.calculateMaxLong(hyperdrive).min(
                underlyingToken.balanceOf(alice)
            )
        );
        underlyingToken.approve(address(token), type(uint256).max);
        // Deposit into the ERC4626 so underlying doesn't need to be used
        token.deposit(basePaid, alice);

        // Establish baseline, important underlying balance must be taken AFTER
        // deposit into ERC4626 token
        uint256 totalPooledAssetsBefore = token.totalAssets();
        uint256 totalSharesBefore = token.convertToShares(
            totalPooledAssetsBefore
        );
        AccountBalances memory aliceBalancesBefore = getAccountBalances(alice);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Open the long
        openLongERC4626(alice, basePaid, false);

        // Ensure balances correctly updated
        verifyDepositShares(
            alice,
            basePaid,
            totalPooledAssetsBefore,
            totalSharesBefore,
            aliceBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_CloseLongWithUnderlying(uint256 basePaid) external {
        vm.startPrank(alice);
        // Alice opens a long.
        basePaid = basePaid.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            HyperdriveUtils.calculateMaxLong(hyperdrive).min(
                underlyingToken.balanceOf(alice)
            )
        );

        // Open a long
        (uint256 maturityTime, uint256 longAmount) = openLongERC4626(
            alice,
            basePaid,
            true
        );

        // Establish a baseline of balances before closing long
        uint256 totalPooledAssetsBefore = token.totalAssets();
        AccountBalances memory aliceBalancesBefore = getAccountBalances(alice);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Close long with underlying assets
        uint256 baseProceeds = hyperdrive.closeLong(
            maturityTime,
            longAmount,
            0,
            alice,
            true,
            new bytes(0)
        );

        // Ensure that the ERC4626 aggregates and the token balances were updated
        // correctly during the trade.
        verifyWithdrawalShares(
            alice,
            baseProceeds,
            totalPooledAssetsBefore,
            aliceBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_CloseLongWithShares(uint256 basePaid) external {
        vm.startPrank(alice);
        // Alice opens a long.
        basePaid = basePaid.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            HyperdriveUtils.calculateMaxLong(hyperdrive).min(
                underlyingToken.balanceOf(alice)
            )
        );

        // Open a long
        (uint256 maturityTime, uint256 longAmount) = openLongERC4626(
            alice,
            basePaid,
            true
        );

        // Establish a baseline of balances before closing long
        uint256 totalPooledAssetsBefore = token.totalAssets();
        uint256 totalSharesBefore = token.convertToShares(
            totalPooledAssetsBefore
        );
        AccountBalances memory aliceBalancesBefore = getAccountBalances(alice);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Close the long
        uint256 baseProceeds = hyperdrive.closeLong(
            maturityTime,
            longAmount,
            0,
            alice,
            false,
            new bytes(0)
        );

        // Ensure balances updated correctly
        verifyWithdrawalToken(
            alice,
            token.convertToShares(baseProceeds),
            totalPooledAssetsBefore,
            totalSharesBefore,
            aliceBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_OpenShortWithUnderlying() external {
        vm.startPrank(alice);
        uint256 shortAmount = 0.001e18;
        shortAmount = shortAmount.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            HyperdriveUtils.calculateMaxShort(hyperdrive).min(
                underlyingToken.balanceOf(alice)
            )
        );

        // Take a baseline
        uint256 totalPooledAssetsBefore = token.totalAssets();
        uint256 totalSharesBefore = token.convertToShares(
            totalPooledAssetsBefore
        );
        AccountBalances memory aliceBalancesBefore = getAccountBalances(alice);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Open a short
        (, uint256 basePaid) = openShortERC4626(alice, shortAmount, true);

        // Ensure that the amount of base paid by the short is reasonable.
        uint256 realizedRate = HyperdriveUtils.calculateAPRFromRealizedPrice(
            shortAmount - basePaid,
            shortAmount,
            1e18
        );

        // Ensure some base was paid
        assertGt(basePaid, 0);
        assertGe(realizedRate, FIXED_RATE);

        // Ensure the balances updated correctly
        verifyDepositUnderlying(
            alice,
            basePaid,
            totalPooledAssetsBefore,
            totalSharesBefore,
            aliceBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_OpenShortWithShares(uint256 shortAmount) external {
        vm.startPrank(alice);
        shortAmount = shortAmount.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            HyperdriveUtils.calculateMaxShort(hyperdrive).min(
                underlyingToken.balanceOf(alice)
            )
        );
        underlyingToken.approve(address(token), type(uint256).max);
        // Deposit into the actual ERC4626 token
        token.deposit(shortAmount, alice);

        // Establish a baseline before we open the short
        uint256 totalPooledAssetsBefore = token.totalAssets();
        uint256 totalSharesBefore = token.convertToShares(
            totalPooledAssetsBefore
        );
        AccountBalances memory aliceBalancesBefore = getAccountBalances(alice);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Open the short
        (, uint256 basePaid) = openShortERC4626(alice, shortAmount, false);

        // Ensure we did actually paid a non-Zero amount of base
        assertGt(basePaid, 0);
        uint256 realizedRate = HyperdriveUtils.calculateAPRFromRealizedPrice(
            shortAmount - basePaid,
            shortAmount,
            1e18
        );
        assertGe(realizedRate, FIXED_RATE);

        // Ensure balances were correctly updated
        verifyDepositShares(
            alice,
            basePaid,
            totalPooledAssetsBefore,
            totalSharesBefore,
            aliceBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_CloseShortWithUnderlying(
        uint256 shortAmount,
        int256 variableRate
    ) external {
        vm.startPrank(alice);
        shortAmount = shortAmount.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            HyperdriveUtils
                .calculateMaxShort(hyperdrive)
                .min(underlyingToken.balanceOf(alice))
                .mulDown(0.95e18)
        );

        (uint256 maturityTime, ) = openShortERC4626(alice, shortAmount, true);
        // The term passes and interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2.5e18);

        // Accumulate yield and let the short mature
        advanceTimeWithYield(POSITION_DURATION);

        // Establish a baseline before closing the short
        uint256 totalPooledAssetsBefore = token.totalAssets();
        AccountBalances memory aliceBalancesBefore = getAccountBalances(alice);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Close the short
        uint256 baseProceeds = hyperdrive.closeShort(
            maturityTime,
            shortAmount,
            0,
            alice,
            true,
            new bytes(0)
        );

        // Ensure that the ERC4626 aggregates and the token balances were updated
        // correctly during the trade.
        verifyWithdrawalShares(
            alice,
            baseProceeds,
            totalPooledAssetsBefore,
            aliceBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_CloseShortWithShares(
        uint256 shortAmount,
        int256 variableRate
    ) external {
        _test_CloseShortWithShares(shortAmount, variableRate);
    }

    function test_CloseShortWithShares_EdgeCases() external {
        uint256 shortAmount = 8300396556459030614636;
        int256 variableRate = 7399321782946468277;
        _test_CloseShortWithShares(shortAmount, variableRate);
    }

    function _test_CloseShortWithShares(
        uint256 shortAmount,
        int256 variableRate
    ) internal {
        vm.startPrank(alice);
        shortAmount = shortAmount.normalizeToRange(
            MINIMUM_TRANSACTION_AMOUNT,
            HyperdriveUtils
                .calculateMaxShort(hyperdrive)
                .min(underlyingToken.balanceOf(alice))
                .mulDown(0.95e18)
        );

        // Deposit into the actual ERC4626
        underlyingToken.approve(address(token), type(uint256).max);
        token.deposit(shortAmount, alice);

        // Open the short
        (uint256 maturityTime, ) = openShortERC4626(alice, shortAmount, false);

        // The term passes and interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2.5e18);

        // Advance time and accumulate the yield
        advanceTimeWithYield(POSITION_DURATION);

        // Establish a baseline before closing the short
        uint256 totalPooledAssetsBefore = token.totalAssets();
        uint256 totalSharesBefore = token.convertToShares(
            totalPooledAssetsBefore
        );
        AccountBalances memory aliceBalancesBefore = getAccountBalances(alice);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Close the short
        uint256 baseProceeds = hyperdrive.closeShort(
            maturityTime,
            shortAmount,
            0,
            alice,
            false,
            new bytes(0)
        );

        // Ensure that the ERC4626 aggregates and the token balances were updated
        // correctly during the trade.
        verifyWithdrawalToken(
            alice,
            token.convertToShares(baseProceeds),
            totalPooledAssetsBefore,
            totalSharesBefore,
            aliceBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function openLongERC4626(
        address trader,
        uint256 baseAmount,
        bool asUnderlying
    ) internal returns (uint256 maturityTime, uint256 bondAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Open the long.
        if (asUnderlying) {
            underlyingToken.approve(address(hyperdrive), baseAmount);
            (maturityTime, bondAmount) = hyperdrive.openLong(
                baseAmount,
                0,
                0,
                trader,
                asUnderlying,
                new bytes(0)
            );
        } else {
            token.approve(address(hyperdrive), baseAmount);
            (maturityTime, bondAmount) = hyperdrive.openLong(
                baseAmount,
                0,
                0,
                trader,
                asUnderlying,
                new bytes(0)
            );
        }

        return (maturityTime, bondAmount);
    }

    function openShortERC4626(
        address trader,
        uint256 bondAmount,
        bool asUnderlying
    ) internal returns (uint256 maturityTime, uint256 baseAmount) {
        vm.stopPrank();
        vm.startPrank(trader);
        // Open the short
        if (asUnderlying) {
            underlyingToken.approve(address(hyperdrive), bondAmount);
            (maturityTime, baseAmount) = hyperdrive.openShort(
                bondAmount,
                type(uint256).max,
                0,
                trader,
                asUnderlying,
                new bytes(0)
            );
        } else {
            token.approve(address(hyperdrive), bondAmount);
            (maturityTime, baseAmount) = hyperdrive.openShort(
                bondAmount,
                type(uint256).max,
                0,
                trader,
                asUnderlying,
                new bytes(0)
            );
        }
        return (maturityTime, baseAmount);
    }

    function verifyDepositUnderlying(
        address trader,
        uint256 basePaid,
        uint256 totalPooledAssetsBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal {
        // Ensure that the amount of assets increased by the base paid.
        assertApproxEqAbs(
            token.totalAssets(),
            totalPooledAssetsBefore + basePaid,
            2
        );

        // Ensure that the underlyingToken balances were updated correctly.
        assertApproxEqAbs(
            underlyingToken.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.underlyingBalance,
            2
        );
        assertApproxEqAbs(
            underlyingToken.balanceOf(trader),
            traderBalancesBefore.underlyingBalance - basePaid,
            2
        );

        // Ensure that the token balances were updated correctly.
        assertApproxEqAbs(
            token.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.shareBalance +
                token.convertToShares(basePaid),
            1
        );
        assertApproxEqAbs(
            token.balanceOf(trader),
            traderBalancesBefore.shareBalance,
            2
        );
        // Ensure that the token shares were updated correctly.
        uint256 expectedShares = basePaid.mulDivDown(
            totalSharesBefore,
            totalPooledAssetsBefore
        );
        assertApproxEqAbs(
            token.convertToShares(token.totalAssets()),
            totalSharesBefore + expectedShares,
            2
        );
        assertApproxEqAbs(
            token.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.shareBalance + expectedShares,
            2
        );
        assertApproxEqAbs(
            token.balanceOf(trader),
            traderBalancesBefore.shareBalance,
            2
        );
    }

    function verifyDepositShares(
        address trader,
        uint256 basePaid,
        uint256 totalPooledAssetsBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal {
        // Ensure that the totalAssets of the token stays the same.
        assertEq(token.totalAssets(), totalPooledAssetsBefore);

        // Ensure that the underlying token balances were updated correctly.
        assertEq(
            underlyingToken.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.underlyingBalance
        );
        assertEq(
            underlyingToken.balanceOf(trader),
            traderBalancesBefore.underlyingBalance
        );

        // Ensure that the token balances were updated correctly.
        assertApproxEqAbs(
            token.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.shareBalance +
                token.convertToShares(basePaid),
            1
        );
        assertApproxEqAbs(
            token.balanceOf(trader),
            traderBalancesBefore.shareBalance - token.convertToShares(basePaid),
            1
        );

        // Ensure that the token shares were updated correctly.
        uint256 expectedShares = basePaid.mulDivDown(
            totalSharesBefore,
            totalPooledAssetsBefore
        );
        assertApproxEqAbs(
            token.convertToShares(token.totalAssets()),
            totalSharesBefore,
            2
        );
        assertApproxEqAbs(
            token.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.shareBalance + expectedShares,
            1
        );
        assertApproxEqAbs(
            token.balanceOf(trader),
            traderBalancesBefore.shareBalance - expectedShares,
            1
        );
    }

    function verifyWithdrawalToken(
        address trader,
        uint256 shareProceeds,
        uint256 totalPooledAssetsBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal {
        // Ensure that the total pooled assets and shares stays the same.
        assertEq(token.totalAssets(), totalPooledAssetsBefore);
        assertApproxEqAbs(
            token.convertToShares(token.totalAssets()),
            totalSharesBefore,
            1
        );

        // Ensure that the underlying balances were updated correctly.
        assertEq(
            underlyingToken.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.underlyingBalance
        );
        assertEq(
            underlyingToken.balanceOf(trader),
            traderBalancesBefore.underlyingBalance
        );

        // Ensure that the token balances were updated correctly.
        assertApproxEqAbs(
            token.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.shareBalance - shareProceeds,
            1
        );
        assertApproxEqAbs(
            token.balanceOf(trader),
            traderBalancesBefore.shareBalance + shareProceeds,
            1
        );
    }

    function verifyWithdrawalShares(
        address trader,
        uint256 baseProceeds,
        uint256 totalPooledAssetsBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal {
        // Allowances are set to 3 due to the expected number of conversions which can occur.
        // Ensure that the total pooled assets decreased by the amount paid out
        assertApproxEqAbs(
            token.totalAssets() + baseProceeds,
            totalPooledAssetsBefore,
            3
        );

        // Ensure that the underlying balances were updated correctly.
        // Token should be converted to underlyingToken and set to the trader
        assertApproxEqAbs(
            underlyingToken.balanceOf(trader),
            traderBalancesBefore.underlyingBalance + baseProceeds,
            3
        );
        assertApproxEqAbs(
            token.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.shareBalance -
                token.convertToShares(baseProceeds),
            3
        );
    }

    struct AccountBalances {
        uint256 shareBalance;
        uint256 underlyingBalance;
    }

    function getAccountBalances(
        address account
    ) internal view returns (AccountBalances memory) {
        return
            AccountBalances({
                shareBalance: token.balanceOf(account),
                underlyingBalance: underlyingToken.balanceOf(account)
            });
    }
}
