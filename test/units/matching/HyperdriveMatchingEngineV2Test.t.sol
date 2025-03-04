// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveMatchingEngineV2 } from "../../../contracts/src/interfaces/IHyperdriveMatchingEngineV2.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMatchingEngineV2 } from "../../../contracts/src/matching/HyperdriveMatchingEngineV2.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract HyperdriveMatchingEngineV2Test is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using SafeERC20 for ERC20;
    using Lib for *;

    /// @dev A salt used to help create orders.
    bytes32 internal constant salt = bytes32(uint256(0xdeadbeef));

    /// @dev The deployed Hyperdrive matching engine.
    HyperdriveMatchingEngineV2 internal matchingEngine;

    /// @notice Sets up the matching engine test with the following actions:
    ///
    ///         1. Deploy and initialize Hyperdrive pool with fees.
    ///         2. Deploy matching engine.
    ///         3. Fund accounts and approve matching engine.
    function setUp() public override {
        super.setUp();

        // Deploy and initialize a Hyperdrive pool with fees.
        IHyperdrive.PoolConfig memory config = testConfig(
            0.05e18,
            POSITION_DURATION
        );
        config.fees.curve = 0.01e18;
        config.fees.flat = 0.0005e18;
        config.fees.governanceLP = 0.15e18;
        deploy(alice, config);
        initialize(alice, 0.05e18, 100_000e18);

        // Deploy matching engine.
        matchingEngine = new HyperdriveMatchingEngineV2(
            "Hyperdrive Matching Engine V2"
        );

        // Fund accounts and approve matching engine.
        address[3] memory accounts = [alice, bob, celine];
        for (uint256 i = 0; i < accounts.length; i++) {
            vm.stopPrank();
            vm.startPrank(accounts[i]);
            baseToken.mint(100_000_000e18);
            baseToken.approve(address(matchingEngine), type(uint256).max);
            baseToken.approve(address(hyperdrive), type(uint256).max);
        }

        vm.recordLogs();
    }

    /// @dev Tests matching orders with open long and open short orders.
    function test_matchOrders_openLongAndOpenShort() public {
        // Create orders.
        IHyperdriveMatchingEngineV2.OrderIntent
            memory longOrder = _createOrderIntent(
                alice,
                address(0),
                100_000e18, // fundAmount.
                95_000e18, // bondAmount.
                IHyperdriveMatchingEngineV2.OrderType.OpenLong
            );

        IHyperdriveMatchingEngineV2.OrderIntent
            memory shortOrder = _createOrderIntent(
                bob,
                address(0),
                101_000e18, // fundAmount.
                95_000e18, // bondAmount.
                IHyperdriveMatchingEngineV2.OrderType.OpenShort
            );

        // Sign orders.
        longOrder.signature = _signOrderIntent(longOrder, alicePK);
        shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

        // Record balances before.
        uint256 aliceBaseBalanceBefore = baseToken.balanceOf(alice);
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 aliceLongBalanceBefore = _getLongBalance(alice);
        uint256 bobShortBalanceBefore = _getShortBalance(bob);

        // Match orders.
        matchingEngine.matchOrders(longOrder, shortOrder, celine);

        // Verify balances after.
        assertLt(baseToken.balanceOf(alice), aliceBaseBalanceBefore);
        assertLt(baseToken.balanceOf(bob), bobBaseBalanceBefore);
        assertGt(_getLongBalance(alice), aliceLongBalanceBefore);
        assertGt(_getShortBalance(bob), bobShortBalanceBefore);
    }

    /// @dev Tests matching orders with close long and close short orders.
    function test_matchOrders_closeLongAndCloseShort() public {
        // First create and match open orders to create positions.
        test_matchOrders_openLongAndOpenShort();

        uint256 maturityTime = hyperdrive.latestCheckpoint() +
            hyperdrive.getPoolConfig().positionDuration;

        // Approve Hyperdrive bonds positions to the matching engine.
        uint256 longAssetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            maturityTime
        );
        uint256 shortAssetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Short,
            maturityTime
        );

        vm.startPrank(alice);
        hyperdrive.setApproval(
            longAssetId,
            address(matchingEngine),
            type(uint256).max
        );
        vm.stopPrank();

        vm.startPrank(bob);
        hyperdrive.setApproval(
            shortAssetId,
            address(matchingEngine),
            type(uint256).max
        );
        vm.stopPrank();

        // Create close orders.
        IHyperdriveMatchingEngineV2.OrderIntent
            memory closeLongOrder = _createOrderIntent(
                alice,
                address(0),
                90_000e18, // min fund amount to receive.
                95_000e18, // bond amount to close.
                IHyperdriveMatchingEngineV2.OrderType.CloseLong
            );
        closeLongOrder.minMaturityTime = maturityTime;
        closeLongOrder.maxMaturityTime = maturityTime;

        IHyperdriveMatchingEngineV2.OrderIntent
            memory closeShortOrder = _createOrderIntent(
                bob,
                address(0),
                5_001e18, // min fund amount to receive.
                95_000e18, // bond amount to close.
                IHyperdriveMatchingEngineV2.OrderType.CloseShort
            );
        closeShortOrder.minMaturityTime = maturityTime;
        closeShortOrder.maxMaturityTime = maturityTime;

        // Sign orders.
        closeLongOrder.signature = _signOrderIntent(closeLongOrder, alicePK);
        closeShortOrder.signature = _signOrderIntent(closeShortOrder, bobPK);

        // Record balances before.
        uint256 aliceBaseBalanceBefore = baseToken.balanceOf(alice);
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 aliceLongBalanceBefore = _getLongBalance(alice);
        uint256 bobShortBalanceBefore = _getShortBalance(bob);

        // Match orders.
        matchingEngine.matchOrders(closeLongOrder, closeShortOrder, celine);

        // Verify balances after.
        assertGt(baseToken.balanceOf(alice), aliceBaseBalanceBefore);
        assertGt(baseToken.balanceOf(bob), bobBaseBalanceBefore);
        assertLt(_getLongBalance(alice), aliceLongBalanceBefore);
        assertLt(_getShortBalance(bob), bobShortBalanceBefore);
    }

    /// @dev Tests matching orders with close long and close short orders with
    ///      different maturity times.
    function test_matchOrders_revertInvalidMaturityTime() public {
        // Create close orders with different maturity times.
        uint256 maturityTime = hyperdrive.latestCheckpoint() +
            hyperdrive.getPoolConfig().positionDuration;

        IHyperdriveMatchingEngineV2.OrderIntent
            memory closeLongOrder = _createOrderIntent(
                alice,
                address(0),
                90_000e18,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.CloseLong
            );
        closeLongOrder.minMaturityTime = maturityTime;
        closeLongOrder.maxMaturityTime = maturityTime;

        IHyperdriveMatchingEngineV2.OrderIntent
            memory closeShortOrder = _createOrderIntent(
                bob,
                address(0),
                90_000e18,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.CloseShort
            );
        closeShortOrder.minMaturityTime = maturityTime + 1 days;
        closeShortOrder.maxMaturityTime = maturityTime + 1 days;

        closeLongOrder.signature = _signOrderIntent(closeLongOrder, alicePK);
        closeShortOrder.signature = _signOrderIntent(closeShortOrder, bobPK);

        vm.expectRevert(
            IHyperdriveMatchingEngineV2.InvalidMaturityTime.selector
        );
        matchingEngine.matchOrders(closeLongOrder, closeShortOrder, celine);
    }

    /// @dev Tests matching orders with insufficient funding.
    function test_matchOrders_failure_insufficientFunding() public {
        // Create orders with insufficient funding.
        IHyperdriveMatchingEngineV2.OrderIntent
            memory longOrder = _createOrderIntent(
                alice,
                address(0),
                1e18, // Very small fundAmount.
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenLong
            );

        IHyperdriveMatchingEngineV2.OrderIntent
            memory shortOrder = _createOrderIntent(
                bob,
                address(0),
                1e18, // Very small fundAmount.
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenShort
            );

        longOrder.signature = _signOrderIntent(longOrder, alicePK);
        shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

        vm.expectRevert(
            IHyperdriveMatchingEngineV2.InsufficientFunding.selector
        );
        matchingEngine.matchOrders(longOrder, shortOrder, celine);
    }

    /// @dev Tests matching orders with valid but different bond amounts
    ///      (partial match).
    function test_matchOrders_differentBondAmounts() public {
        // Create orders with different bond amounts - this should succeed with
        // partial matching.
        IHyperdriveMatchingEngineV2.OrderIntent
            memory longOrder = _createOrderIntent(
                alice,
                address(0),
                100_000e18,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenLong
            );

        IHyperdriveMatchingEngineV2.OrderIntent
            memory shortOrder = _createOrderIntent(
                bob,
                address(0),
                100_000e18,
                90_000e18, // Different but valid bond amount.
                IHyperdriveMatchingEngineV2.OrderType.OpenShort
            );

        longOrder.signature = _signOrderIntent(longOrder, alicePK);
        shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

        // Record balances before.
        uint256 aliceLongBalanceBefore = _getLongBalance(alice);
        uint256 bobShortBalanceBefore = _getShortBalance(bob);

        // Match orders - should succeed with partial match.
        matchingEngine.matchOrders(longOrder, shortOrder, celine);

        // Verify partial fill - should match the smaller of the two amounts.
        assertGe(_getLongBalance(alice) - aliceLongBalanceBefore, 90_000e18);
        assertGe(_getShortBalance(bob) - bobShortBalanceBefore, 90_000e18);
    }

    /// @dev Tests matching orders with invalid bond amounts (exceeds available
    ///      balance).
    function test_matchOrders_failure_invalidBondAmount() public {
        // First create some positions.
        test_matchOrders_openLongAndOpenShort();

        uint256 maturityTime = hyperdrive.latestCheckpoint() +
            hyperdrive.getPoolConfig().positionDuration;

        // Approve Hyperdrive bonds positions to the matching engine.
        uint256 longAssetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            maturityTime
        );
        uint256 shortAssetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Short,
            maturityTime
        );

        vm.startPrank(alice);
        hyperdrive.setApproval(
            longAssetId,
            address(matchingEngine),
            type(uint256).max
        );
        vm.stopPrank();

        vm.startPrank(bob);
        hyperdrive.setApproval(
            shortAssetId,
            address(matchingEngine),
            type(uint256).max
        );
        vm.stopPrank();

        // Try to close more bonds than available.
        IHyperdriveMatchingEngineV2.OrderIntent
            memory closeLongOrder = _createOrderIntent(
                alice,
                address(0),
                100_000e18,
                200_000e18, // More than what alice has.
                IHyperdriveMatchingEngineV2.OrderType.CloseLong
            );
        closeLongOrder.minMaturityTime = maturityTime;
        closeLongOrder.maxMaturityTime = maturityTime;

        IHyperdriveMatchingEngineV2.OrderIntent
            memory closeShortOrder = _createOrderIntent(
                bob,
                address(0),
                100_000e18,
                200_000e18,
                IHyperdriveMatchingEngineV2.OrderType.CloseShort
            );
        closeShortOrder.minMaturityTime = maturityTime;
        closeShortOrder.maxMaturityTime = maturityTime;

        closeLongOrder.signature = _signOrderIntent(closeLongOrder, alicePK);
        closeShortOrder.signature = _signOrderIntent(closeShortOrder, bobPK);

        // Should revert because traders don't have enough bonds.
        // @dev TODO: Looks like there is no good error code to use for this
        //          expected revert, as the error is just an arithmetic underflow?
        vm.expectRevert();
        matchingEngine.matchOrders(closeLongOrder, closeShortOrder, celine);
    }

    /// @dev Tests matching orders with expired orders.
    function test_matchOrders_failure_alreadyExpired() public {
        IHyperdriveMatchingEngineV2.OrderIntent
            memory longOrder = _createOrderIntent(
                alice,
                address(0),
                100_000e18,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenLong
            );
        longOrder.expiry = block.timestamp - 1; // Already expired.

        IHyperdriveMatchingEngineV2.OrderIntent
            memory shortOrder = _createOrderIntent(
                bob,
                address(0),
                100_000e18,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenShort
            );

        longOrder.signature = _signOrderIntent(longOrder, alicePK);
        shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

        vm.expectRevert(IHyperdriveMatchingEngineV2.AlreadyExpired.selector);
        matchingEngine.matchOrders(longOrder, shortOrder, celine);
    }

    /// @dev Tests matching orders with mismatched Hyperdrive instances.
    function test_matchOrders_failure_mismatchedHyperdrive() public {
        IHyperdriveMatchingEngineV2.OrderIntent
            memory longOrder = _createOrderIntent(
                alice,
                address(0),
                100_000e18,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenLong
            );

        IHyperdriveMatchingEngineV2.OrderIntent
            memory shortOrder = _createOrderIntent(
                bob,
                address(0),
                100_000e18,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenShort
            );
        shortOrder.hyperdrive = IHyperdrive(address(0xdead)); // Different Hyperdrive instance.

        longOrder.signature = _signOrderIntent(longOrder, alicePK);
        shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

        vm.expectRevert(
            IHyperdriveMatchingEngineV2.MismatchedHyperdrive.selector
        );
        matchingEngine.matchOrders(longOrder, shortOrder, celine);
    }

    /// @dev Tests successful partial matching of orders.
    function test_matchOrders_partialMatch() public {
        // Create orders where one has larger amount than the other.
        IHyperdriveMatchingEngineV2.OrderIntent
            memory longOrder = _createOrderIntent(
                alice,
                address(0),
                100_000e18,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenLong
            );

        IHyperdriveMatchingEngineV2.OrderIntent
            memory shortOrder = _createOrderIntent(
                bob,
                address(0),
                50_000e18, // Half the amount.
                47_500e18, // Half the bonds.
                IHyperdriveMatchingEngineV2.OrderType.OpenShort
            );

        longOrder.signature = _signOrderIntent(longOrder, alicePK);
        shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

        // Record balances before.
        uint256 aliceLongBalanceBefore = _getLongBalance(alice);
        uint256 bobShortBalanceBefore = _getShortBalance(bob);

        // Match orders.
        matchingEngine.matchOrders(longOrder, shortOrder, celine);

        // Verify partial fill.
        assertGe(_getLongBalance(alice) - aliceLongBalanceBefore, 47_500e18);
        assertGe(_getShortBalance(bob) - bobShortBalanceBefore, 47_500e18);

        // Verify order is not fully cancelled for alice.
        bytes32 orderHash = matchingEngine.hashOrderIntent(longOrder);
        assertFalse(matchingEngine.isCancelled(orderHash));
    }

    /// @dev Tests matching orders with invalid vault share price.
    function test_matchOrders_failure_invalidVaultSharePrice() public {
        IHyperdriveMatchingEngineV2.OrderIntent
            memory longOrder = _createOrderIntent(
                alice,
                address(0),
                100_000e18,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenLong
            );
        longOrder.minVaultSharePrice = type(uint256).max; // Unreasonably high min vault share price.

        IHyperdriveMatchingEngineV2.OrderIntent
            memory shortOrder = _createOrderIntent(
                bob,
                address(0),
                100_000e18,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenShort
            );
        shortOrder.minVaultSharePrice = type(uint256).max; // Unreasonably high min vault share price.

        longOrder.signature = _signOrderIntent(longOrder, alicePK);
        shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

        vm.expectRevert(IHyperdrive.MinimumSharePrice.selector);
        matchingEngine.matchOrders(longOrder, shortOrder, celine);
    }

    /// @dev Tests matching orders with invalid signatures.
    function test_matchOrders_failure_invalidSignature() public {
        IHyperdriveMatchingEngineV2.OrderIntent
            memory longOrder = _createOrderIntent(
                alice,
                address(0),
                100_000e18,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenLong
            );

        IHyperdriveMatchingEngineV2.OrderIntent
            memory shortOrder = _createOrderIntent(
                bob,
                address(0),
                100_000e18,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenShort
            );

        // Sign with wrong private keys.
        longOrder.signature = _signOrderIntent(longOrder, bobPK); // Wrong signer.
        shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

        vm.expectRevert(IHyperdriveMatchingEngineV2.InvalidSignature.selector);
        matchingEngine.matchOrders(longOrder, shortOrder, celine);
    }

    /// @dev Tests matching orders with OpenLong + CloseLong (transfer case)
    /// @dev Tests matching orders with OpenLong + CloseLong (transfer case)
    function test_matchOrders_openLongAndCloseLong() public {
        // First create a long position for alice
        test_matchOrders_openLongAndOpenShort();

        uint256 maturityTime = hyperdrive.latestCheckpoint() +
            hyperdrive.getPoolConfig().positionDuration;

        // Approve matching engine for alice's long position
        uint256 longAssetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            maturityTime
        );

        vm.startPrank(alice);
        hyperdrive.setApproval(
            longAssetId,
            address(matchingEngine),
            type(uint256).max
        );
        vm.stopPrank();

        // Create orders
        IHyperdriveMatchingEngineV2.OrderIntent
            memory openLongOrder = _createOrderIntent(
                bob, // bob wants to open long
                address(0),
                100_000e18,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenLong
            );

        IHyperdriveMatchingEngineV2.OrderIntent
            memory closeLongOrder = _createOrderIntent(
                alice, // alice wants to close her long
                address(0),
                90_000e18,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.CloseLong
            );
        closeLongOrder.minMaturityTime = maturityTime;
        closeLongOrder.maxMaturityTime = maturityTime;

        // Sign orders
        openLongOrder.signature = _signOrderIntent(openLongOrder, bobPK);
        closeLongOrder.signature = _signOrderIntent(closeLongOrder, alicePK);

        // Record balances before
        uint256 aliceBaseBalanceBefore = baseToken.balanceOf(alice);
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 aliceLongBalanceBefore = _getLongBalance(alice);
        uint256 bobLongBalanceBefore = _getLongBalance(bob);

        // Match orders
        matchingEngine.matchOrders(openLongOrder, closeLongOrder, celine);

        // Verify balances
        assertGt(baseToken.balanceOf(alice), aliceBaseBalanceBefore); // alice receives payment
        assertLt(baseToken.balanceOf(bob), bobBaseBalanceBefore); // bob pays
        assertLt(_getLongBalance(alice), aliceLongBalanceBefore); // alice's long position decreases
        assertGt(_getLongBalance(bob), bobLongBalanceBefore); // bob receives long position
    }

    /// @dev Fuzzing test to verify TOKEN_AMOUNT_BUFFER is sufficient
    function testFuzz_tokenAmountBuffer(uint256 bondAmount) public {
        bondAmount = bound(bondAmount, 100e18, 1_000_000e18);
        uint256 fundAmount1 = bondAmount / 2;
        (, uint256 cost) = _calculateMintCost(bondAmount, true);
        uint256 fundAmount2 = cost + 10 - fundAmount1;

        // Create orders
        IHyperdriveMatchingEngineV2.OrderIntent
            memory longOrder = _createOrderIntent(
                alice,
                address(0),
                fundAmount1,
                bondAmount,
                IHyperdriveMatchingEngineV2.OrderType.OpenLong
            );

        IHyperdriveMatchingEngineV2.OrderIntent
            memory shortOrder = _createOrderIntent(
                bob,
                address(0),
                fundAmount2,
                bondAmount,
                IHyperdriveMatchingEngineV2.OrderType.OpenShort
            );

        // Sign orders
        longOrder.signature = _signOrderIntent(longOrder, alicePK);
        shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

        // Match orders should not revert due to insufficient buffer
        matchingEngine.matchOrders(longOrder, shortOrder, celine);
    }

    /// @dev Tests fillOrder with OpenLong maker and OpenShort taker
    function test_fillOrder_openLongMakerOpenShortTaker() public {
        // Create maker order
        IHyperdriveMatchingEngineV2.OrderIntent
            memory makerOrder = _createOrderIntent(
                alice,
                address(0),
                93_000e18,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenLong
            );
        makerOrder.signature = _signOrderIntent(makerOrder, alicePK);

        // Create minimal taker order
        IHyperdriveMatchingEngineV2.OrderIntent
            memory takerOrder = _createOrderIntent(
                bob,
                address(0),
                0, // Not needed for immediate fill
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenShort
            );

        // Record balances before
        uint256 aliceBaseBalanceBefore = baseToken.balanceOf(alice);
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 aliceLongBalanceBefore = _getLongBalance(alice);
        uint256 bobShortBalanceBefore = _getShortBalance(bob);

        // Fill order
        vm.startPrank(bob);
        matchingEngine.fillOrder(makerOrder, takerOrder);
        vm.stopPrank();

        // Verify balances
        assertLt(baseToken.balanceOf(alice), aliceBaseBalanceBefore);
        assertLt(baseToken.balanceOf(bob), bobBaseBalanceBefore);
        assertGt(_getLongBalance(alice), aliceLongBalanceBefore);
        assertGt(_getShortBalance(bob), bobShortBalanceBefore);
    }

    /// @dev Tests fillOrder with OpenShort maker and OpenLong taker
    function test_fillOrder_openShortMakerOpenLongTaker() public {
        // Create maker order
        IHyperdriveMatchingEngineV2.OrderIntent
            memory makerOrder = _createOrderIntent(
                alice,
                address(0),
                2_000e18,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenShort
            );
        makerOrder.signature = _signOrderIntent(makerOrder, alicePK);

        // Create minimal taker order
        IHyperdriveMatchingEngineV2.OrderIntent
            memory takerOrder = _createOrderIntent(
                bob,
                address(0),
                0, // Not needed for immediate fill
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenLong
            );

        // Record balances before
        uint256 aliceBaseBalanceBefore = baseToken.balanceOf(alice);
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 aliceShortBalanceBefore = _getShortBalance(alice);
        uint256 bobLongBalanceBefore = _getLongBalance(bob);

        // Fill order
        vm.startPrank(bob);
        matchingEngine.fillOrder(makerOrder, takerOrder);
        vm.stopPrank();

        // Verify balances
        assertLt(baseToken.balanceOf(alice), aliceBaseBalanceBefore);
        assertLt(baseToken.balanceOf(bob), bobBaseBalanceBefore);
        assertGt(_getLongBalance(bob), bobLongBalanceBefore);
        assertGt(_getShortBalance(alice), aliceShortBalanceBefore);
    }

    /// @dev Tests fillOrder failure cases
    function test_fillOrder_failures() public {
        IHyperdriveMatchingEngineV2.OrderIntent
            memory makerOrder = _createOrderIntent(
                alice,
                address(0),
                100_000e18,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenLong
            );
        makerOrder.signature = _signOrderIntent(makerOrder, alicePK);

        // Test invalid order combination
        IHyperdriveMatchingEngineV2.OrderIntent
            memory invalidTakerOrder = _createOrderIntent(
                bob,
                address(0),
                0,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenLong // Same as maker
            );

        vm.startPrank(bob);
        vm.expectRevert(
            IHyperdriveMatchingEngineV2.InvalidOrderCombination.selector
        );
        matchingEngine.fillOrder(makerOrder, invalidTakerOrder);
        vm.stopPrank();

        // Test expired order
        makerOrder.expiry = block.timestamp - 1;
        IHyperdriveMatchingEngineV2.OrderIntent
            memory validTakerOrder = _createOrderIntent(
                bob,
                address(0),
                0,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenShort
            );

        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveMatchingEngineV2.AlreadyExpired.selector);
        matchingEngine.fillOrder(makerOrder, validTakerOrder);
        vm.stopPrank();
    }

    /// @dev Tests fillOrder with partial fill
    function test_fillOrder_partialFill() public {
        // Create maker order with large amount
        IHyperdriveMatchingEngineV2.OrderIntent
            memory makerOrder = _createOrderIntent(
                alice,
                address(0),
                200_000e18,
                190_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenLong
            );
        makerOrder.signature = _signOrderIntent(makerOrder, alicePK);

        // Create taker order with smaller amount
        IHyperdriveMatchingEngineV2.OrderIntent
            memory takerOrder = _createOrderIntent(
                bob,
                address(0),
                0,
                95_000e18, // Half of maker's amount
                IHyperdriveMatchingEngineV2.OrderType.OpenShort
            );

        // Record balances and order state before
        uint256 aliceLongBalanceBefore = _getLongBalance(alice);
        bytes32 orderHash = matchingEngine.hashOrderIntent(makerOrder);
        (uint128 bondAmountUsedBefore, ) = matchingEngine.orderAmountsUsed(
            orderHash
        );

        // Fill order
        vm.startPrank(bob);
        matchingEngine.fillOrder(makerOrder, takerOrder);
        vm.stopPrank();

        // Verify partial fill
        (uint128 bondAmountUsedAfter, ) = matchingEngine.orderAmountsUsed(
            orderHash
        );
        assertGe(bondAmountUsedAfter - bondAmountUsedBefore, 95_000e18);
        assertEq(
            _getLongBalance(alice) - aliceLongBalanceBefore,
            bondAmountUsedAfter
        );

        // Verify order can still be filled further
        assertFalse(matchingEngine.isCancelled(orderHash));
    }

    /// @dev Tests fillOrder with maturity time constraints
    function test_fillOrder_maturityTimeConstraints() public {
        uint256 currentTime = block.timestamp;
        uint256 minMaturityTime = currentTime + 1 days;
        uint256 maxMaturityTime = currentTime + 7 days;

        // Create maker order with maturity time constraints
        IHyperdriveMatchingEngineV2.OrderIntent
            memory makerOrder = _createOrderIntent(
                alice,
                address(0),
                100_000e18,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenLong
            );
        makerOrder.minMaturityTime = minMaturityTime;
        makerOrder.maxMaturityTime = maxMaturityTime;
        makerOrder.signature = _signOrderIntent(makerOrder, alicePK);

        // Test taker order with invalid maturity time
        IHyperdriveMatchingEngineV2.OrderIntent
            memory invalidTakerOrder = _createOrderIntent(
                bob,
                address(0),
                0,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenShort
            );
        // Set maturity time to be outside of maker's range, and actually
        // it does not matter, as the taker's maturity time is not checked
        // in this case.
        invalidTakerOrder.minMaturityTime = maxMaturityTime + 1 days;
        invalidTakerOrder.maxMaturityTime = maxMaturityTime + 2 days;

        // Will revert because the test config has position duration of 365 days.
        vm.expectRevert(
            IHyperdriveMatchingEngineV2.InvalidMaturityTime.selector
        );
        vm.startPrank(bob);
        matchingEngine.fillOrder(makerOrder, invalidTakerOrder);
        vm.stopPrank();

        // Test with valid maturity time
        maxMaturityTime = currentTime + 365 days;
        makerOrder.maxMaturityTime = maxMaturityTime;
        makerOrder.signature = _signOrderIntent(makerOrder, alicePK);

        IHyperdriveMatchingEngineV2.OrderIntent
            memory validTakerOrder = _createOrderIntent(
                bob,
                address(0),
                0,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenShort
            );
        validTakerOrder.minMaturityTime = maxMaturityTime + 1 days;
        validTakerOrder.maxMaturityTime = maxMaturityTime + 2 days;

        vm.startPrank(bob);
        matchingEngine.fillOrder(makerOrder, validTakerOrder);
        vm.stopPrank();
    }

    /// @dev Tests fillOrder with counterparty restriction
    function test_fillOrder_counterpartyRestriction() public {
        // Create maker order with specific counterparty
        IHyperdriveMatchingEngineV2.OrderIntent
            memory makerOrder = _createOrderIntent(
                alice,
                bob, // Only bob can fill
                100_000e18,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenLong
            );
        makerOrder.signature = _signOrderIntent(makerOrder, alicePK);

        // Try to fill with wrong counterparty (celine)
        IHyperdriveMatchingEngineV2.OrderIntent
            memory invalidTakerOrder = _createOrderIntent(
                celine,
                address(0),
                0,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenShort
            );

        vm.expectRevert(
            IHyperdriveMatchingEngineV2.InvalidCounterparty.selector
        );
        vm.startPrank(celine);
        matchingEngine.fillOrder(makerOrder, invalidTakerOrder);
        vm.stopPrank();

        // Fill with correct counterparty (bob)
        IHyperdriveMatchingEngineV2.OrderIntent
            memory validTakerOrder = _createOrderIntent(
                bob,
                address(0),
                0,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenShort
            );

        vm.startPrank(bob);
        matchingEngine.fillOrder(makerOrder, validTakerOrder);
        vm.stopPrank();
    }

    /// @dev Tests fillOrder with custom destination address
    function test_fillOrder_customDestination() public {
        // Create maker order with custom destination
        IHyperdriveMatchingEngineV2.OrderIntent
            memory makerOrder = _createOrderIntent(
                alice,
                address(0),
                100_000e18,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenLong
            );
        makerOrder.options.destination = celine; // Positions go to celine
        makerOrder.signature = _signOrderIntent(makerOrder, alicePK);

        // Create taker order with custom destination
        IHyperdriveMatchingEngineV2.OrderIntent
            memory takerOrder = _createOrderIntent(
                bob,
                address(0),
                0,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenShort
            );
        takerOrder.options.destination = address(0xdead); // Positions go to 0xdead

        // Record balances before
        uint256 celineLongBalanceBefore = _getLongBalance(celine);
        uint256 deadShortBalanceBefore = _getShortBalance(address(0xdead));

        // Fill order
        vm.startPrank(bob);
        matchingEngine.fillOrder(makerOrder, takerOrder);
        vm.stopPrank();

        // Verify positions went to correct destinations
        assertGt(_getLongBalance(celine), celineLongBalanceBefore);
        assertGt(_getShortBalance(address(0xdead)), deadShortBalanceBefore);
        assertEq(_getLongBalance(alice), 0);
        assertEq(_getShortBalance(bob), 0);
    }

    /// @dev Tests fillOrder with multiple fills until completion
    function test_fillOrder_multipleFilsUntilCompletion() public {
        // Create large maker order
        IHyperdriveMatchingEngineV2.OrderIntent
            memory makerOrder = _createOrderIntent(
                alice,
                address(0),
                300_000e18,
                285_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenLong
            );
        makerOrder.signature = _signOrderIntent(makerOrder, alicePK);

        // Fill order in three parts
        for (uint256 i = 0; i < 3; i++) {
            IHyperdriveMatchingEngineV2.OrderIntent
                memory takerOrder = _createOrderIntent(
                    bob,
                    address(0),
                    0,
                    95_000e18,
                    IHyperdriveMatchingEngineV2.OrderType.OpenShort
                );

            vm.startPrank(bob);
            matchingEngine.fillOrder(makerOrder, takerOrder);
            vm.stopPrank();
        }

        // Verify order is now fully filled
        bytes32 orderHash = matchingEngine.hashOrderIntent(makerOrder);
        (uint128 bondAmountUsed, ) = matchingEngine.orderAmountsUsed(orderHash);
        assertGe(bondAmountUsed, 285_000e18);

        // Try to fill again
        IHyperdriveMatchingEngineV2.OrderIntent
            memory finalTakerOrder = _createOrderIntent(
                bob,
                address(0),
                0,
                95_000e18,
                IHyperdriveMatchingEngineV2.OrderType.OpenShort
            );

        vm.expectRevert(
            IHyperdriveMatchingEngineV2.AlreadyFullyExecuted.selector
        );
        vm.startPrank(bob);
        matchingEngine.fillOrder(makerOrder, finalTakerOrder);
        vm.stopPrank();
    }

    // Helper functions.

    /// @dev Creates an order intent.
    /// @param trader The address of the trader.
    /// @param counterparty The address of the counterparty.
    /// @param fundAmount The amount of base tokens to fund the order.
    /// @param bondAmount The amount of bonds to fund the order.
    /// @param orderType The type of the order.
    /// @return The order intent.
    function _createOrderIntent(
        address trader,
        address counterparty,
        uint256 fundAmount,
        uint256 bondAmount,
        IHyperdriveMatchingEngineV2.OrderType orderType
    ) internal view returns (IHyperdriveMatchingEngineV2.OrderIntent memory) {
        return
            IHyperdriveMatchingEngineV2.OrderIntent({
                trader: trader,
                counterparty: counterparty,
                hyperdrive: hyperdrive,
                fundAmount: fundAmount,
                bondAmount: bondAmount,
                minVaultSharePrice: 0,
                options: IHyperdrive.Options({
                    destination: trader,
                    asBase: true,
                    extraData: ""
                }),
                orderType: orderType,
                minMaturityTime: 0,
                maxMaturityTime: type(uint256).max,
                signature: "",
                expiry: block.timestamp + 1 days,
                salt: salt
            });
    }

    /// @dev Gets the balance of long bonds for an account.
    /// @param account The address of the account.
    /// @return The balance of long bonds for the account.
    function _getLongBalance(address account) internal view returns (uint256) {
        uint256 maturityTime = hyperdrive.latestCheckpoint() +
            hyperdrive.getPoolConfig().positionDuration;
        return
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
                account
            );
    }

    /// @dev Gets the balance of short bonds for an account.
    /// @param account The address of the account.
    /// @return The balance of short bonds for the account.
    function _getShortBalance(address account) internal view returns (uint256) {
        uint256 maturityTime = hyperdrive.latestCheckpoint() +
            hyperdrive.getPoolConfig().positionDuration;
        return
            hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    maturityTime
                ),
                account
            );
    }

    /// @dev Signs an order intent.
    /// @param order The order intent to sign.
    /// @param privateKey The private key of the signer.
    /// @return The signature of the order intent.
    function _signOrderIntent(
        IHyperdriveMatchingEngineV2.OrderIntent memory order,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 digest = matchingEngine.hashOrderIntent(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Calculates the cost and parameters for minting positions.
    /// @param _bondMatchAmount The amount of bonds to mint.
    /// @param _asBase Whether the cost is in terms of base.
    /// @return maturityTime The maturity time for new positions.
    /// @return cost The total cost including fees.
    function _calculateMintCost(
        uint256 _bondMatchAmount,
        bool _asBase
    ) internal view returns (uint256 maturityTime, uint256 cost) {
        // Get pool configuration.
        IHyperdrive.PoolConfig memory config = hyperdrive.getPoolConfig();

        // Calculate checkpoint and maturity time.
        uint256 latestCheckpoint = hyperdrive.latestCheckpoint();
        maturityTime = latestCheckpoint + config.positionDuration;

        // Get vault share prices.
        uint256 vaultSharePrice = hyperdrive.convertToBase(1e18);
        uint256 openVaultSharePrice = hyperdrive
            .getCheckpoint(latestCheckpoint)
            .vaultSharePrice;
        if (openVaultSharePrice == 0) {
            openVaultSharePrice = vaultSharePrice;
        }

        // Calculate the required fund amount.
        // NOTE: Round the required fund amount up to overestimate the cost.
        cost = _bondMatchAmount.mulDivUp(
            vaultSharePrice.max(openVaultSharePrice),
            openVaultSharePrice
        );

        // Add flat fee.
        // NOTE: Round the flat fee calculation up to match other flows.
        uint256 flatFee = _bondMatchAmount.mulUp(config.fees.flat);
        cost += flatFee;

        // Add governance fee.
        // NOTE: Round the governance fee calculation down to match other flows.
        uint256 governanceFee = 2 * flatFee.mulDown(config.fees.governanceLP);
        cost += governanceFee;

        if (_asBase) {
            // NOTE: Round up to overestimate the cost.
            cost = hyperdrive.convertToBase(cost.divUp(vaultSharePrice));
        } else {
            // NOTE: Round up to overestimate the cost.
            cost = cost.divUp(vaultSharePrice);
        }
    }
}
