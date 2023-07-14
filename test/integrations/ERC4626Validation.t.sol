// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC4626 } from "contracts/src/interfaces/IERC4626.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { ERC4626HyperdriveDeployer } from "contracts/src/factory/ERC4626HyperdriveDeployer.sol";
import { ERC4626HyperdriveFactory } from "contracts/src/factory/ERC4626HyperdriveFactory.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
import { HyperdriveTest } from "../utils/HyperdriveTest.sol";
import { MockERC4626Hyperdrive } from "../mocks/Mock4626Hyperdrive.sol";
import { HyperdriveUtils } from "../utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";
import { console } from "forge-std/console.sol";

abstract contract ERC4626ValidationTest is HyperdriveTest {
    using FixedPointMath for *;
    using Lib for *;

    ERC4626HyperdriveFactory internal factory;
    IERC20 internal underlyingToken;
    IERC4626 internal token;
    MockERC4626Hyperdrive hyperdriveInstance;

    uint256 internal constant FIXED_RATE = 0.05e18;

    function advanceTimeWithYield(uint256 timeDelta) public virtual;

    function test_deployAndInitialize() external {
        vm.startPrank(alice);

        IHyperdrive.PoolConfig memory config = testConfig(FIXED_RATE);
        config.baseToken = underlyingToken;
        config.initialSharePrice = FixedPointMath.ONE_18.divDown(
            token.convertToShares(FixedPointMath.ONE_18)
        );

        uint256 contribution = 10_000e18; // Revisit

        underlyingToken.approve(address(factory), type(uint256).max);

        hyperdrive = factory.deployAndInitialize(
            config,
            new bytes32[](0),
            contribution,
            FIXED_RATE
        );

        assertEq(
            hyperdrive.getPoolInfo().lpTotalSupply,
            hyperdrive.getPoolInfo().shareReserves - config.minimumShareReserves
        );

        // Verify that the correct events were emitted.
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
            0.00001e18,
            min(
                HyperdriveUtils.calculateMaxLong(hyperdrive),
                underlyingToken.balanceOf(alice)
            )
        );

        openLongERC4626(alice, basePaid, true);

        verifyDepositUnderlying(
            alice,
            basePaid,
            totalPooledAssetsBefore,
            totalSharesBefore,
            aliceBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_OpenLongWithToken(uint256 basePaid) external {
        vm.startPrank(alice);
        basePaid = basePaid.normalizeToRange(
            0.00001e18,
            min(
                HyperdriveUtils.calculateMaxLong(hyperdrive),
                underlyingToken.balanceOf(alice)
            )
        );
        underlyingToken.approve(address(token), type(uint256).max);
        token.deposit(basePaid, alice);

        uint256 totalPooledAssetsBefore = token.totalAssets();
        uint256 totalSharesBefore = token.convertToShares(
            totalPooledAssetsBefore
        );
        AccountBalances memory aliceBalancesBefore = getAccountBalances(alice);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        openLongERC4626(alice, basePaid, false);

        verifyDepositActual(
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
            0.00001e18,
            min(
                HyperdriveUtils.calculateMaxLong(hyperdrive),
                underlyingToken.balanceOf(alice)
            )
        );
        (uint256 maturityTime, uint256 longAmount) = openLongERC4626(
            alice,
            basePaid,
            true
        );

        hyperdrive.closeLong(maturityTime, longAmount, 0, alice, true);
    }

    function test_CloseLongWithToken(uint256 basePaid) external {
        vm.startPrank(alice);
        // Alice opens a long.
        basePaid = basePaid.normalizeToRange(
            0.00001e18,
            min(
                HyperdriveUtils.calculateMaxLong(hyperdrive),
                underlyingToken.balanceOf(alice)
            )
        );
        (uint256 maturityTime, uint256 longAmount) = openLongERC4626(
            alice,
            basePaid,
            true
        );

        uint256 totalPooledAssetsBefore = token.totalAssets();
        uint256 totalSharesBefore = token.convertToShares(
            totalPooledAssetsBefore
        );
        AccountBalances memory aliceBalancesBefore = getAccountBalances(alice);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        uint256 baseProceeds = hyperdrive.closeLong(
            maturityTime,
            longAmount,
            0,
            alice,
            false
        );

        verifyTokenWithdrawal(
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
            0.00001e18,
            min(
                HyperdriveUtils.calculateMaxShort(hyperdrive),
                underlyingToken.balanceOf(alice)
            )
        );

        uint256 totalPooledAssetsBefore = token.totalAssets();
        uint256 totalSharesBefore = token.convertToShares(
            totalPooledAssetsBefore
        );
        AccountBalances memory aliceBalancesBefore = getAccountBalances(alice);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        (, uint256 basePaid) = openShortERC4626(alice, shortAmount, true);

        // Ensure that the amount of base paid by the short is reasonable.
        uint256 realizedRate = HyperdriveUtils.calculateAPRFromRealizedPrice(
            shortAmount - basePaid,
            shortAmount,
            1e18
        );

        assertGt(basePaid, 0);
        assertGe(realizedRate, FIXED_RATE);
        verifyDepositUnderlying(
            alice,
            basePaid,
            totalPooledAssetsBefore,
            totalSharesBefore,
            aliceBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test_OpenShortWithToken(uint256 shortAmount) external {
        vm.startPrank(alice);
        shortAmount = shortAmount.normalizeToRange(
            0.00001e18,
            min(
                HyperdriveUtils.calculateMaxShort(hyperdrive),
                underlyingToken.balanceOf(alice)
            )
        );

        underlyingToken.approve(address(token), type(uint256).max);
        token.deposit(shortAmount, alice);

        uint256 totalPooledAssetsBefore = token.totalAssets();
        uint256 totalSharesBefore = token.convertToShares(
            totalPooledAssetsBefore
        );
        AccountBalances memory aliceBalancesBefore = getAccountBalances(alice);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        (, uint256 basePaid) = openShortERC4626(alice, shortAmount, false);

        assertGt(basePaid, 0);

        verifyDepositActual(
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
            0.00001e18,
            min(
                HyperdriveUtils.calculateMaxShort(hyperdrive),
                underlyingToken.balanceOf(alice)
            )
        );

        (uint256 maturityTime, ) = openShortERC4626(alice, shortAmount, true);
        // The term passes and interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2.5e18);

        advanceTimeWithYield(POSITION_DURATION);

        hyperdrive.closeShort(maturityTime, shortAmount, 0, alice, true);
    }

    function test_CloseShortWithToken(
        uint256 shortAmount,
        int256 variableRate
    ) external {
        vm.startPrank(alice);
        shortAmount = shortAmount.normalizeToRange(
            0.00001e18,
            min(
                HyperdriveUtils.calculateMaxShort(hyperdrive),
                underlyingToken.balanceOf(alice)
            )
        );

        underlyingToken.approve(address(token), type(uint256).max);
        token.deposit(shortAmount, alice);
        (uint256 maturityTime, ) = openShortERC4626(alice, shortAmount, true);
        // The term passes and interest accrues.
        variableRate = variableRate.normalizeToRange(0, 2.5e18);

        advanceTimeWithYield(POSITION_DURATION);

        uint256 totalPooledAssetsBefore = token.totalAssets();
        uint256 totalSharesBefore = token.convertToShares(
            totalPooledAssetsBefore
        );
        AccountBalances memory aliceBalancesBefore = getAccountBalances(alice);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        uint256 baseProceeds = hyperdrive.closeShort(
            maturityTime,
            shortAmount,
            0,
            alice,
            false
        );

        // Ensure that the ERC4626 aggregates and the token balances were updated
        // correctly during the trade.
        verifyTokenWithdrawal(
            alice,
            token.convertToShares(baseProceeds),
            totalPooledAssetsBefore,
            totalSharesBefore,
            aliceBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    /* Helper Functions for dealing with Forked ERC4626 behavior */
    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function openLongERC4626(
        address trader,
        uint256 baseAmount,
        bool asUnderlying
    ) internal returns (uint256 maturityTime, uint256 bondAmount) {
        vm.stopPrank();
        vm.startPrank(trader);

        // Open the long.
        maturityTime = HyperdriveUtils.maturityTimeFromLatestCheckpoint(
            hyperdrive
        );
        uint256 bondBalanceBefore = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            trader
        );
        if (asUnderlying) {
            underlyingToken.approve(address(hyperdrive), baseAmount);
            hyperdrive.openLong(baseAmount, 0, trader, asUnderlying);
        } else {
            token.approve(address(hyperdrive), baseAmount);
            hyperdrive.openLong(baseAmount, 0, trader, asUnderlying);
        }
        uint256 bondBalanceAfter = hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            trader
        );
        return (maturityTime, bondBalanceAfter.sub(bondBalanceBefore));
    }

    function openShortERC4626(
        address trader,
        uint256 bondAmount,
        bool asUnderlying
    ) internal returns (uint256 maturityTime, uint256 baseAmount) {
        vm.stopPrank();
        vm.startPrank(trader);
        // Open the short
        maturityTime = HyperdriveUtils.maturityTimeFromLatestCheckpoint(
            hyperdrive
        );
        if (asUnderlying) {
            underlyingToken.approve(address(hyperdrive), bondAmount);
            (maturityTime, baseAmount) = hyperdrive.openShort(
                bondAmount,
                type(uint256).max,
                trader,
                asUnderlying
            );
        } else {
            token.approve(address(hyperdrive), bondAmount);
            (maturityTime, baseAmount) = hyperdrive.openShort(
                bondAmount,
                type(uint256).max,
                trader,
                asUnderlying
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
            hyperdriveBalancesBefore.underlyingTokenBalance,
            2
        );
        assertEq(
            underlyingToken.balanceOf(trader),
            traderBalancesBefore.underlyingTokenBalance - basePaid
        );

        // Ensure that the token balances were updated correctly.
        assertApproxEqAbs(
            token.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.tokenBalance + basePaid,
            1
        );
        assertApproxEqAbs(
            token.balanceOf(trader),
            traderBalancesBefore.tokenBalance,
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
            token.convertToShares(token.balanceOf(address(hyperdrive))),
            hyperdriveBalancesBefore.shares + expectedShares,
            2
        );
        assertApproxEqAbs(
            token.convertToShares(token.balanceOf(trader)),
            traderBalancesBefore.shares,
            2
        );
    }

    function verifyDepositActual(
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
            hyperdriveBalancesBefore.underlyingTokenBalance
        );
        assertEq(
            underlyingToken.balanceOf(trader),
            traderBalancesBefore.underlyingTokenBalance
        );

        // Ensure that the token balances were updated correctly.
        assertApproxEqAbs(
            token.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.tokenBalance + basePaid,
            1
        );
        assertApproxEqAbs(
            token.balanceOf(trader),
            traderBalancesBefore.tokenBalance - basePaid,
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
            token.convertToShares(token.balanceOf(address(hyperdrive))),
            hyperdriveBalancesBefore.shares + expectedShares,
            1
        );
        assertApproxEqAbs(
            token.convertToShares(token.balanceOf(trader)),
            traderBalancesBefore.shares - expectedShares,
            1
        );
    }

    function verifyTokenWithdrawal(
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

        // Ensure that the token balances were updated correctly.
        assertEq(
            underlyingToken.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.underlyingTokenBalance
        );
        assertEq(
            underlyingToken.balanceOf(trader),
            traderBalancesBefore.underlyingTokenBalance
        );

        // Ensure that the token balances were updated correctly.
        assertApproxEqAbs(
            token.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.tokenBalance - shareProceeds,
            1
        );
        assertApproxEqAbs(
            token.balanceOf(trader),
            traderBalancesBefore.tokenBalance + shareProceeds,
            1
        );

        // Ensure that the token shares were updated correctly.
        uint256 expectedShares = shareProceeds.mulDivDown(
            totalSharesBefore,
            totalPooledAssetsBefore
        );
        assertApproxEqAbs(
            token.convertToShares(token.balanceOf(address(hyperdrive))),
            hyperdriveBalancesBefore.shares - expectedShares,
            2
        );
        assertApproxEqAbs(
            token.convertToShares(token.balanceOf(trader)),
            traderBalancesBefore.shares + expectedShares,
            2
        );
    }

    struct AccountBalances {
        uint256 shares;
        uint256 tokenBalance;
        uint256 underlyingTokenBalance;
    }

    function getAccountBalances(
        address account
    ) internal view returns (AccountBalances memory) {
        return
            AccountBalances({
                shares: token.convertToShares(token.balanceOf(account)),
                tokenBalance: token.balanceOf(account),
                underlyingTokenBalance: underlyingToken.balanceOf(account)
            });
    }
}
