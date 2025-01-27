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

    bytes32 internal constant salt = bytes32(uint256(0xdeadbeef));
    HyperdriveMatchingEngineV2 internal matchingEngine;

    function setUp() public override {
        super.setUp();

        // Deploy and initialize a Hyperdrive pool with fees
        IHyperdrive.PoolConfig memory config = testConfig(0.05e18, POSITION_DURATION);
        config.fees.curve = 0.01e18;
        config.fees.flat = 0.0005e18;
        config.fees.governanceLP = 0.15e18;
        deploy(alice, config);
        initialize(alice, 0.05e18, 100_000e18);

        // Deploy matching engine
        matchingEngine = new HyperdriveMatchingEngineV2("Hyperdrive Matching Engine V2");

        // Fund accounts and approve matching engine
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

    function test_matchOrders_openLongAndOpenShort() public {
        // Create orders
        IHyperdriveMatchingEngineV2.OrderIntent memory longOrder = _createOrderIntent(
            alice,
            address(0),
            address(0),
            100_000e18,  // fundAmount
            95_000e18,   // bondAmount
            IHyperdriveMatchingEngineV2.OrderType.OpenLong
        );
        
        IHyperdriveMatchingEngineV2.OrderIntent memory shortOrder = _createOrderIntent(
            bob,
            address(0),
            address(0),
            101_000e18,  // fundAmount
            95_000e18,   // bondAmount
            IHyperdriveMatchingEngineV2.OrderType.OpenShort
        );

        // Sign orders
        longOrder.signature = _signOrderIntent(longOrder, alicePK);
        shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

        // Record balances before
        uint256 aliceBaseBalanceBefore = baseToken.balanceOf(alice);
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 aliceLongBalanceBefore = _getLongBalance(alice);
        uint256 bobShortBalanceBefore = _getShortBalance(bob);

        // Match orders
        matchingEngine.matchOrders(longOrder, shortOrder, celine);

        // Verify balances after
        assertLt(baseToken.balanceOf(alice), aliceBaseBalanceBefore);
        assertLt(baseToken.balanceOf(bob), bobBaseBalanceBefore);
        assertGt(_getLongBalance(alice), aliceLongBalanceBefore);
        assertGt(_getShortBalance(bob), bobShortBalanceBefore);
    }

    function test_matchOrders_closeLongAndCloseShort() public {
        // First create and match open orders to create positions
        test_matchOrders_openLongAndOpenShort();

        uint256 maturityTime = hyperdrive.latestCheckpoint() + hyperdrive.getPoolConfig().positionDuration;
        
        // Create close orders
        IHyperdriveMatchingEngineV2.OrderIntent memory closeLongOrder = _createOrderIntent(
            alice,
            address(0),
            address(0),
            90_000e18,   // min fund amount to receive
            95_000e18,   // bond amount to close
            IHyperdriveMatchingEngineV2.OrderType.CloseLong
        );
        closeLongOrder.minMaturityTime = maturityTime;
        closeLongOrder.maxMaturityTime = maturityTime;

        IHyperdriveMatchingEngineV2.OrderIntent memory closeShortOrder = _createOrderIntent(
            bob,
            address(0),
            address(0),
            90_000e18,   // min fund amount to receive
            95_000e18,   // bond amount to close
            IHyperdriveMatchingEngineV2.OrderType.CloseShort
        );
        closeShortOrder.minMaturityTime = maturityTime;
        closeShortOrder.maxMaturityTime = maturityTime;

        // Sign orders
        closeLongOrder.signature = _signOrderIntent(closeLongOrder, alicePK);
        closeShortOrder.signature = _signOrderIntent(closeShortOrder, bobPK);

        // Record balances before
        uint256 aliceBaseBalanceBefore = baseToken.balanceOf(alice);
        uint256 bobBaseBalanceBefore = baseToken.balanceOf(bob);
        uint256 aliceLongBalanceBefore = _getLongBalance(alice);
        uint256 bobShortBalanceBefore = _getShortBalance(bob);

        // Match orders
        matchingEngine.matchOrders(closeLongOrder, closeShortOrder, celine);

        // Verify balances after
        assertGt(baseToken.balanceOf(alice), aliceBaseBalanceBefore);
        assertGt(baseToken.balanceOf(bob), bobBaseBalanceBefore);
        assertLt(_getLongBalance(alice), aliceLongBalanceBefore);
        assertLt(_getShortBalance(bob), bobShortBalanceBefore);
    }

    function test_matchOrders_revertInvalidMaturityTime() public {
        // Create close orders with different maturity times
        uint256 maturityTime = hyperdrive.latestCheckpoint() + hyperdrive.getPoolConfig().positionDuration;
        
        IHyperdriveMatchingEngineV2.OrderIntent memory closeLongOrder = _createOrderIntent(
            alice,
            address(0),
            address(0),
            90_000e18,
            95_000e18,
            IHyperdriveMatchingEngineV2.OrderType.CloseLong
        );
        closeLongOrder.minMaturityTime = maturityTime;
        closeLongOrder.maxMaturityTime = maturityTime;

        IHyperdriveMatchingEngineV2.OrderIntent memory closeShortOrder = _createOrderIntent(
            bob,
            address(0),
            address(0),
            90_000e18,
            95_000e18,
            IHyperdriveMatchingEngineV2.OrderType.CloseShort
        );
        closeShortOrder.minMaturityTime = maturityTime + 1 days;
        closeShortOrder.maxMaturityTime = maturityTime + 1 days;

        closeLongOrder.signature = _signOrderIntent(closeLongOrder, alicePK);
        closeShortOrder.signature = _signOrderIntent(closeShortOrder, bobPK);

        vm.expectRevert(IHyperdriveMatchingEngineV2.InvalidMaturityTime.selector);
        matchingEngine.matchOrders(closeLongOrder, closeShortOrder, celine);
    }

    /// @dev Tests matching orders with insufficient funding
    function test_matchOrders_failure_insufficientFunding() public {
        // Create orders with insufficient funding
        IHyperdriveMatchingEngineV2.OrderIntent memory longOrder = _createOrderIntent(
            alice,
            address(0),
            address(0),
            1e18,  // Very small fundAmount
            95_000e18,   
            IHyperdriveMatchingEngineV2.OrderType.OpenLong
        );
        
        IHyperdriveMatchingEngineV2.OrderIntent memory shortOrder = _createOrderIntent(
            bob,
            address(0),
            address(0),
            1e18,  // Very small fundAmount
            95_000e18,   
            IHyperdriveMatchingEngineV2.OrderType.OpenShort
        );

        longOrder.signature = _signOrderIntent(longOrder, alicePK);
        shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

        vm.expectRevert(IHyperdriveMatchingEngineV2.InsufficientFunding.selector);
        matchingEngine.matchOrders(longOrder, shortOrder, celine);
    }

    /// @dev Tests matching orders with valid but different bond amounts 
    ///      (partial match)
    function test_matchOrders_differentBondAmounts() public {
        // Create orders with different bond amounts - this should succeed with
        // partial matching
        IHyperdriveMatchingEngineV2.OrderIntent memory longOrder = _createOrderIntent(
            alice,
            address(0),
            address(0),
            100_000e18,
            95_000e18,
            IHyperdriveMatchingEngineV2.OrderType.OpenLong
        );
        
        IHyperdriveMatchingEngineV2.OrderIntent memory shortOrder = _createOrderIntent(
            bob,
            address(0),
            address(0),
            100_000e18,
            90_000e18, // Different but valid bond amount
            IHyperdriveMatchingEngineV2.OrderType.OpenShort
        );

        longOrder.signature = _signOrderIntent(longOrder, alicePK);
        shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

        // Record balances before
        uint256 aliceLongBalanceBefore = _getLongBalance(alice);
        uint256 bobShortBalanceBefore = _getShortBalance(bob);

        // Match orders - should succeed with partial match
        matchingEngine.matchOrders(longOrder, shortOrder, celine);

        // Verify partial fill - should match the smaller of the two amounts
        assertEq(_getLongBalance(alice) - aliceLongBalanceBefore, 90_000e18);
        assertEq(_getShortBalance(bob) - bobShortBalanceBefore, 90_000e18);
    }

    /// @dev Tests matching orders with invalid bond amounts (exceeds available
    ///      balance)
    function test_matchOrders_failure_invalidBondAmount() public {
        // First create some positions
        test_matchOrders_openLongAndOpenShort();
        
        uint256 maturityTime = hyperdrive.latestCheckpoint() + hyperdrive.getPoolConfig().positionDuration;
        
        // Try to close more bonds than available
        IHyperdriveMatchingEngineV2.OrderIntent memory closeLongOrder = _createOrderIntent(
            alice,
            address(0),
            address(0),
            100_000e18,
            200_000e18, // More than what alice has
            IHyperdriveMatchingEngineV2.OrderType.CloseLong
        );
        closeLongOrder.minMaturityTime = maturityTime;
        closeLongOrder.maxMaturityTime = maturityTime;
        
        IHyperdriveMatchingEngineV2.OrderIntent memory closeShortOrder = _createOrderIntent(
            bob,
            address(0),
            address(0),
            100_000e18,
            200_000e18,
            IHyperdriveMatchingEngineV2.OrderType.CloseShort
        );
        closeShortOrder.minMaturityTime = maturityTime;
        closeShortOrder.maxMaturityTime = maturityTime;

        closeLongOrder.signature = _signOrderIntent(closeLongOrder, alicePK);
        closeShortOrder.signature = _signOrderIntent(closeShortOrder, bobPK);

        // Should revert because traders don't have enough bonds
        vm.expectRevert(IHyperdrive.InsufficientBalance.selector);
        matchingEngine.matchOrders(closeLongOrder, closeShortOrder, celine);
    }

    /// @dev Tests matching orders with expired orders
    function test_matchOrders_failure_alreadyExpired() public {
        IHyperdriveMatchingEngineV2.OrderIntent memory longOrder = _createOrderIntent(
            alice,
            address(0),
            address(0),
            100_000e18,
            95_000e18,
            IHyperdriveMatchingEngineV2.OrderType.OpenLong
        );
        longOrder.expiry = block.timestamp - 1; // Already expired
        
        IHyperdriveMatchingEngineV2.OrderIntent memory shortOrder = _createOrderIntent(
            bob,
            address(0),
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

    /// @dev Tests matching orders with mismatched Hyperdrive instances
    function test_matchOrders_failure_mismatchedHyperdrive() public {
        IHyperdriveMatchingEngineV2.OrderIntent memory longOrder = _createOrderIntent(
            alice,
            address(0),
            address(0),
            100_000e18,
            95_000e18,
            IHyperdriveMatchingEngineV2.OrderType.OpenLong
        );
        
        IHyperdriveMatchingEngineV2.OrderIntent memory shortOrder = _createOrderIntent(
            bob,
            address(0),
            address(0),
            100_000e18,
            95_000e18,
            IHyperdriveMatchingEngineV2.OrderType.OpenShort
        );
        shortOrder.hyperdrive = IHyperdrive(address(0xdead)); // Different Hyperdrive instance

        longOrder.signature = _signOrderIntent(longOrder, alicePK);
        shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

        vm.expectRevert(IHyperdriveMatchingEngineV2.MismatchedHyperdrive.selector);
        matchingEngine.matchOrders(longOrder, shortOrder, celine);
    }

    /// @dev Tests successful partial matching of orders
    function test_matchOrders_partialMatch() public {
        // Create orders where one has larger amount than the other
        IHyperdriveMatchingEngineV2.OrderIntent memory longOrder = _createOrderIntent(
            alice,
            address(0),
            address(0),
            100_000e18,
            95_000e18,
            IHyperdriveMatchingEngineV2.OrderType.OpenLong
        );
        
        IHyperdriveMatchingEngineV2.OrderIntent memory shortOrder = _createOrderIntent(
            bob,
            address(0),
            address(0),
            50_000e18, // Half the amount
            47_500e18, // Half the bonds
            IHyperdriveMatchingEngineV2.OrderType.OpenShort
        );

        longOrder.signature = _signOrderIntent(longOrder, alicePK);
        shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

        // Record balances before
        uint256 aliceLongBalanceBefore = _getLongBalance(alice);
        uint256 bobShortBalanceBefore = _getShortBalance(bob);

        // Match orders
        matchingEngine.matchOrders(longOrder, shortOrder, celine);

        // Verify partial fill
        assertEq(_getLongBalance(alice) - aliceLongBalanceBefore, 47_500e18);
        assertEq(_getShortBalance(bob) - bobShortBalanceBefore, 47_500e18);
        
        // Verify order is not fully cancelled for alice
        bytes32 orderHash = matchingEngine.hashOrderIntent(longOrder);
        assertFalse(matchingEngine.isCancelled(orderHash));
    }

    /// @dev Tests matching orders with invalid vault share price
    function test_matchOrders_failure_invalidVaultSharePrice() public {
        IHyperdriveMatchingEngineV2.OrderIntent memory longOrder = _createOrderIntent(
            alice,
            address(0),
            address(0),
            100_000e18,
            95_000e18,
            IHyperdriveMatchingEngineV2.OrderType.OpenLong
        );
        longOrder.minVaultSharePrice = type(uint256).max; // Unreasonably high min vault share price
        
        IHyperdriveMatchingEngineV2.OrderIntent memory shortOrder = _createOrderIntent(
            bob,
            address(0),
            address(0),
            100_000e18,
            95_000e18,
            IHyperdriveMatchingEngineV2.OrderType.OpenShort
        );

        longOrder.signature = _signOrderIntent(longOrder, alicePK);
        shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

        vm.expectRevert(IHyperdrive.MinimumSharePrice.selector);
        matchingEngine.matchOrders(longOrder, shortOrder, celine);
    }

    /// @dev Tests matching orders with invalid signatures
    function test_matchOrders_failure_invalidSignature() public {
        IHyperdriveMatchingEngineV2.OrderIntent memory longOrder = _createOrderIntent(
            alice,
            address(0),
            address(0),
            100_000e18,
            95_000e18,
            IHyperdriveMatchingEngineV2.OrderType.OpenLong
        );
        
        IHyperdriveMatchingEngineV2.OrderIntent memory shortOrder = _createOrderIntent(
            bob,
            address(0),
            address(0),
            100_000e18,
            95_000e18,
            IHyperdriveMatchingEngineV2.OrderType.OpenShort
        );

        // Sign with wrong private keys
        longOrder.signature = _signOrderIntent(longOrder, bobPK); // Wrong signer
        shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

        vm.expectRevert(IHyperdriveMatchingEngineV2.InvalidSignature.selector);
        matchingEngine.matchOrders(longOrder, shortOrder, celine);
    }

    // Helper functions
    function _createOrderIntent(
        address trader,
        address counterparty,
        address feeRecipient,
        uint256 fundAmount,
        uint256 bondAmount,
        IHyperdriveMatchingEngineV2.OrderType orderType
    ) internal view returns (IHyperdriveMatchingEngineV2.OrderIntent memory) {
        return IHyperdriveMatchingEngineV2.OrderIntent({
            trader: trader,
            counterparty: counterparty,
            feeRecipient: feeRecipient,
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

    function _getLongBalance(address account) internal view returns (uint256) {
        uint256 maturityTime = hyperdrive.latestCheckpoint() + hyperdrive.getPoolConfig().positionDuration;
        return hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            account
        );
    }

    function _getShortBalance(address account) internal view returns (uint256) {
        uint256 maturityTime = hyperdrive.latestCheckpoint() + hyperdrive.getPoolConfig().positionDuration;
        return hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, maturityTime),
            account
        );
    }

    function _signOrderIntent(
        IHyperdriveMatchingEngineV2.OrderIntent memory order,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 digest = matchingEngine.hashOrderIntent(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
} 