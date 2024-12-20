// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { VmSafe } from "forge-std/Vm.sol";
import { IMorpho } from "morpho-blue/src/interfaces/IMorpho.sol";
import { IMorphoFlashLoanCallback } from "morpho-blue/src/interfaces/IMorphoCallbacks.sol";
import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveMatchingEngine } from "../../../contracts/src/interfaces/IHyperdriveMatchingEngine.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMatchingEngine } from "../../../contracts/src/matching/HyperdriveMatchingEngine.sol";
import { HyperdriveTest } from "../../utils/HyperdriveTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract FlashLoaner {
    using SafeERC20 for ERC20;

    /// @notice Allows anyone to take out a flash loan. This must be paid back
    ///         by the end of the transaction.
    /// @param _token The token that is flash borrowed.
    /// @param _assets The amount of assets flash borrowed.
    /// @param _data The data for the flash loan callback.
    function flashLoan(
        ERC20 _token,
        uint256 _assets,
        bytes calldata _data
    ) external {
        // Send the flash loan to the account.
        _token.safeTransfer(msg.sender, _assets);

        // Call the callback.
        IMorphoFlashLoanCallback(msg.sender).onMorphoFlashLoan(_assets, _data);

        // Transfer the tokens back to this contract.
        _token.safeTransferFrom(msg.sender, address(this), _assets);
    }
}

contract EIP1271Signer {
    using SafeERC20 for ERC20;

    /// @notice A flag indicating whether signature validation should succeed or
    ///         fail.
    bool public shouldVerifySignature = true;

    /// @notice Calls `matchingEngine.cancelOrders` with the provided orders.
    /// @param _matchingEngine The matching engine where the orders should be
    ///        cancelled.
    /// @param _orders The orders to cancel.
    function cancelOrders(
        IHyperdriveMatchingEngine _matchingEngine,
        IHyperdriveMatchingEngine.OrderIntent[] memory _orders
    ) external {
        _matchingEngine.cancelOrders(_orders);
    }

    /// @notice Approves a specified token with a specified amount.
    /// @param _token The token to approve.
    /// @param _target The target of the approval.
    /// @param _amount The amount to approve.
    function approve(ERC20 _token, address _target, uint256 _amount) external {
        _token.forceApprove(_target, _amount);
    }

    /// @notice Sets `shouldVerifySignature` to the provided value.
    /// @param _value The updated value.
    function setShouldVerifySignature(bool _value) external {
        shouldVerifySignature = _value;
    }

    /// @notice Returns whether the signature provided is valid.
    /// @return The magic value if the signature verified and zero otherwise.
    function isValidSignature(
        bytes32,
        bytes memory
    ) external view returns (bytes4) {
        if (shouldVerifySignature) {
            return this.isValidSignature.selector;
        } else {
            return bytes4(0);
        }
    }
}

/// @dev This test suite provides coverage for the different paths through the
///      matching engine's code. It uses the normal test harness with a mocked
///      out EIP1271 signer and flash loaner to test all of the different cases.
contract HyperdriveMatchingEngineTest is HyperdriveTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    /// @dev Emitted when orders are cancelled
    event OrdersCancelled(address indexed trader, bytes32[] orderHashes);

    /// @dev Emitted when orders are matched
    event OrdersMatched(
        IHyperdrive indexed hyperdrive,
        bytes32 indexed longOrderHash,
        bytes32 indexed shortOrderHash,
        address long,
        address short
    );

    /// @dev A salt used to help create orders.
    bytes32 internal salt = bytes32(uint256(0xdeadbeef));

    /// @dev The deployer EIP1271 signer.
    EIP1271Signer internal signer;

    /// @dev The deployed Hyperdrive matching engine.
    IHyperdriveMatchingEngine internal matchingEngine;

    /// @notice Sets up the matching engine test with the following actions:
    ///
    ///         1. Deploy and initialize Hyperdrive pool with fees.
    ///         2. Deploy and fund a flash loaner contract.
    ///         3. Deploy a Hyperdrive matching engine.
    ///         4. Fund some EOA accounts with base tokens.
    ///         5. Deploy and fund an EIP1271 signer.
    function setUp() public override {
        // Run the higher level setup.
        super.setUp();

        // Deploy and initialize a Hyperdrive pool with fees.
        IHyperdrive.PoolConfig memory config = testConfig(
            0.05e18,
            POSITION_DURATION
        );
        config.fees.curve = 0.01e18;
        config.fees.flat = 0.0005e18;
        config.fees.governanceLP = 0.15e18;
        config.fees.governanceZombie = 0.03e18;
        deploy(alice, config);
        initialize(alice, 0.05e18, 100_000e18);

        // Deploy a flash loan contract and seed it with lots of base tokens.
        IMorpho flashLoaner = IMorpho(address(new FlashLoaner()));
        baseToken.mint(address(flashLoaner), 100_000_000e18);

        // Deploy the Hyperdrive matching engine.
        matchingEngine = IHyperdriveMatchingEngine(
            new HyperdriveMatchingEngine(
                "Hyperdrive Matching Engine",
                flashLoaner
            )
        );

        // Fund Alice, Bob, and Celine with base tokens and approve the matching
        // engine.
        address[3] memory accounts = [alice, bob, celine];
        for (uint256 i = 0; i < accounts.length; i++) {
            vm.stopPrank();
            vm.startPrank(accounts[i]);
            baseToken.mint(100_000_000e18);
            baseToken.approve(address(matchingEngine), type(uint256).max);
        }

        // Deploy and fund a EIP1271 signer and approve the matching engine on
        // their behalf.
        signer = new EIP1271Signer();
        baseToken.mint(address(signer), 100_000_000e18);
        signer.approve(
            ERC20(address(baseToken)),
            address(matchingEngine),
            type(uint256).max
        );

        // Start recording event logs.
        vm.recordLogs();
    }

    /// @dev Ensures that orders can't be cancelled by anyone other than the
    ///      sender.
    function test_cancelOrders_failure_invalidSender() external {
        // Create an order that can be used for testing several cases.
        IHyperdriveMatchingEngine.OrderIntent memory order = _createOrderIntent(
            alice,
            100_000e18,
            105_000e18,
            IHyperdriveMatchingEngine.OrderType.OpenLong
        );
        IHyperdriveMatchingEngine.OrderIntent[]
            memory orders = new IHyperdriveMatchingEngine.OrderIntent[](1);
        orders[0] = order;

        // Ensure that Bob can't cancel Alice's order.
        order.signature = _signOrderIntent(order, bobPK);
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(IHyperdriveMatchingEngine.InvalidSender.selector);
        matchingEngine.cancelOrders(orders);

        // Ensure cancelling fails when EIP1271 signer isn't the order's trader.
        signer.setShouldVerifySignature(false);
        order.signature = hex"deadbeef";
        vm.expectRevert(IHyperdriveMatchingEngine.InvalidSender.selector);
        signer.cancelOrders(matchingEngine, orders);
    }

    /// @dev Ensures that orders can't be cancelled without providing a valid
    ///      signature.
    function test_cancelOrders_failure_invalidSignature() external {
        // Create an order that can be used for testing several cases.
        IHyperdriveMatchingEngine.OrderIntent memory order = _createOrderIntent(
            alice,
            100_000e18,
            105_000e18,
            IHyperdriveMatchingEngine.OrderType.OpenLong
        );
        IHyperdriveMatchingEngine.OrderIntent[]
            memory orders = new IHyperdriveMatchingEngine.OrderIntent[](1);
        orders[0] = order;

        // Ensure cancelling fails with an empty signature for an EOA.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert();
        matchingEngine.cancelOrders(orders);

        // Ensure cancelling fails with a malformed signature for an EOA.
        order.signature = hex"deadbeef";
        vm.expectRevert();
        matchingEngine.cancelOrders(orders);

        // Ensure cancelling fails when the wrong account signs the order.
        order.signature = _signOrderIntent(order, bobPK);
        vm.expectRevert(IHyperdriveMatchingEngine.InvalidSignature.selector);
        matchingEngine.cancelOrders(orders);

        // Ensure cancelling fails when EIP1271 signer doesn't approve.
        signer.setShouldVerifySignature(false);
        order.trader = address(signer);
        order.signature = hex"deadbeef";
        vm.expectRevert(IHyperdriveMatchingEngine.InvalidSignature.selector);
        signer.cancelOrders(matchingEngine, orders);
    }

    /// @dev Ensures that an EOA can cancel an order they create.
    function test_cancelOrders_success_eoaOrder() external {
        // Create an EOA order.
        IHyperdriveMatchingEngine.OrderIntent memory order = _createOrderIntent(
            alice,
            100_000e18,
            105_000e18,
            IHyperdriveMatchingEngine.OrderType.OpenLong
        );
        order.signature = _signOrderIntent(order, alicePK);
        IHyperdriveMatchingEngine.OrderIntent[]
            memory orders = new IHyperdriveMatchingEngine.OrderIntent[](1);
        orders[0] = order;

        // Ensure that Alice can cancel her order.
        vm.stopPrank();
        vm.startPrank(alice);
        matchingEngine.cancelOrders(orders);

        // Ensure the correct event was emitted.
        _verifyCancelOrdersEvent(alice, orders);

        // Ensure that the order was cancelled.
        assertTrue(
            matchingEngine.isCancelled(matchingEngine.hashOrderIntent(order))
        );
    }

    /// @dev Ensures that an EIP1271 signer can cancel an order they create.
    function test_cancelOrders_success_eip1271Order() external {
        // Create an EOA order.
        IHyperdriveMatchingEngine.OrderIntent memory order = _createOrderIntent(
            address(signer),
            100_000e18,
            105_000e18,
            IHyperdriveMatchingEngine.OrderType.OpenLong
        );
        order.signature = hex"deadbeef";
        IHyperdriveMatchingEngine.OrderIntent[]
            memory orders = new IHyperdriveMatchingEngine.OrderIntent[](1);
        orders[0] = order;

        // Ensure that the EIP1271 signer can cancel their order.
        vm.stopPrank();
        vm.startPrank(alice);
        signer.cancelOrders(matchingEngine, orders);

        // Ensure the correct event was emitted.
        _verifyCancelOrdersEvent(address(signer), orders);

        // Ensure that the order was cancelled.
        assertTrue(
            matchingEngine.isCancelled(matchingEngine.hashOrderIntent(order))
        );
    }

    /// @dev Ensures that multiple orders can be cancelled simultanesouly by
    ///      EOAs and EIP1271 signers.
    function test_cancelOrders_success_multipleOrders() external {
        // An EOA successfully cancels several orders.
        {
            // The EOA creates and cancels several orders.
            IHyperdriveMatchingEngine.OrderIntent[]
                memory orders = new IHyperdriveMatchingEngine.OrderIntent[](3);
            orders[0] = _createOrderIntent(
                address(alice),
                100_000e18,
                105_000e18,
                IHyperdriveMatchingEngine.OrderType.OpenLong
            );
            orders[0].signature = _signOrderIntent(orders[0], alicePK);
            orders[1] = _createOrderIntent(
                address(alice),
                100_000e18,
                200_000e18,
                IHyperdriveMatchingEngine.OrderType.OpenLong
            );
            orders[1].signature = _signOrderIntent(orders[1], alicePK);
            orders[2] = _createOrderIntent(
                address(alice),
                100_000e18,
                105_000e18,
                IHyperdriveMatchingEngine.OrderType.OpenLong
            );
            orders[2].signature = _signOrderIntent(orders[2], alicePK);
            vm.stopPrank();
            vm.startPrank(alice);
            matchingEngine.cancelOrders(orders);

            // Ensure the correct event was emitted.
            _verifyCancelOrdersEvent(address(alice), orders);

            // Ensure that the orders were cancelled.
            for (uint256 i = 0; i < orders.length; i++) {
                assertTrue(
                    matchingEngine.isCancelled(
                        matchingEngine.hashOrderIntent(orders[i])
                    )
                );
            }
        }

        // An EIP1271 signer cancels several orders.
        {
            // The EIP1271 signer cancels several orders.
            IHyperdriveMatchingEngine.OrderIntent[]
                memory orders = new IHyperdriveMatchingEngine.OrderIntent[](3);
            orders[0] = _createOrderIntent(
                address(signer),
                100_000e18,
                105_000e18,
                IHyperdriveMatchingEngine.OrderType.OpenLong
            );
            orders[0].signature = hex"deadbeef";
            orders[1] = _createOrderIntent(
                address(signer),
                100_000e18,
                200_000e18,
                IHyperdriveMatchingEngine.OrderType.OpenLong
            );
            orders[1].signature = hex"deadbeef";
            orders[2] = _createOrderIntent(
                address(signer),
                100_000e18,
                105_000e18,
                IHyperdriveMatchingEngine.OrderType.OpenLong
            );
            orders[2].signature = hex"deadbeef";
            vm.stopPrank();
            vm.startPrank(alice);
            signer.cancelOrders(matchingEngine, orders);

            // Ensure the correct event was emitted.
            _verifyCancelOrdersEvent(address(signer), orders);

            // Ensure that the orders were cancelled.
            for (uint256 i = 0; i < orders.length; i++) {
                assertTrue(
                    matchingEngine.isCancelled(
                        matchingEngine.hashOrderIntent(orders[i])
                    )
                );
            }
        }
    }

    /// @dev Ensures that order matching fails when one or both of the orders
    ///      have the wrong order type.
    function test_matchOrders_failure_invalidOrderType() external {
        // Create two orders that can be used for this test.
        IHyperdriveMatchingEngine.OrderIntent
            memory longOrder = _createOrderIntent(
                alice,
                100_000e18,
                0,
                IHyperdriveMatchingEngine.OrderType.OpenLong
            );
        IHyperdriveMatchingEngine.OrderIntent
            memory shortOrder = _createOrderIntent(
                bob,
                105_000e18,
                type(uint256).max,
                IHyperdriveMatchingEngine.OrderType.OpenShort
            );

        // Ensure that order matching fails when the long order type is wrong.
        longOrder.orderType = IHyperdriveMatchingEngine.OrderType.OpenShort;
        vm.expectRevert(IHyperdriveMatchingEngine.InvalidOrderType.selector);
        matchingEngine.matchOrders(
            // long order
            longOrder,
            // short order
            shortOrder,
            // LP amount
            2_000_000e18,
            // add liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // remove liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // fee recipient
            celine,
            true
        );

        // Ensure that order matching fails when the short order type is wrong.
        longOrder.orderType = IHyperdriveMatchingEngine.OrderType.OpenLong;
        shortOrder.orderType = IHyperdriveMatchingEngine.OrderType.OpenLong;
        vm.expectRevert(IHyperdriveMatchingEngine.InvalidOrderType.selector);
        matchingEngine.matchOrders(
            // long order
            longOrder,
            // short order
            shortOrder,
            // LP amount
            2_000_000e18,
            // add liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // remove liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // fee recipient
            celine,
            true
        );

        // Ensure that order matching fails when both order types are wrong.
        longOrder.orderType = IHyperdriveMatchingEngine.OrderType.OpenShort;
        shortOrder.orderType = IHyperdriveMatchingEngine.OrderType.OpenLong;
        vm.expectRevert(IHyperdriveMatchingEngine.InvalidOrderType.selector);
        matchingEngine.matchOrders(
            // long order
            longOrder,
            // short order
            shortOrder,
            // LP amount
            2_000_000e18,
            // add liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // remove liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // fee recipient
            celine,
            true
        );
    }

    /// @dev Ensures that order matching fails when one or both of the orders
    ///      are expired.
    function test_matchOrders_failure_alreadyExpired() external {
        // Create two orders that can be used for this test.
        IHyperdriveMatchingEngine.OrderIntent
            memory longOrder = _createOrderIntent(
                alice,
                100_000e18,
                0,
                IHyperdriveMatchingEngine.OrderType.OpenLong
            );
        IHyperdriveMatchingEngine.OrderIntent
            memory shortOrder = _createOrderIntent(
                bob,
                105_000e18,
                type(uint256).max,
                IHyperdriveMatchingEngine.OrderType.OpenShort
            );

        // Ensure that order matching fails when the long order is expired.
        longOrder.expiry = block.timestamp - 1 days;
        vm.expectRevert(IHyperdriveMatchingEngine.AlreadyExpired.selector);
        matchingEngine.matchOrders(
            // long order
            longOrder,
            // short order
            shortOrder,
            // LP amount
            2_000_000e18,
            // add liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // remove liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // fee recipient
            celine,
            true
        );

        // Ensure that order matching fails when the short order is expired.
        longOrder.expiry = block.timestamp + 1 days;
        shortOrder.expiry = block.timestamp;
        vm.expectRevert(IHyperdriveMatchingEngine.AlreadyExpired.selector);
        matchingEngine.matchOrders(
            // long order
            longOrder,
            // short order
            shortOrder,
            // LP amount
            2_000_000e18,
            // add liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // remove liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // fee recipient
            celine,
            true
        );

        // Ensure that order matching fails when both orders are expired.
        longOrder.expiry = block.timestamp - 365 days;
        shortOrder.expiry = block.timestamp;
        vm.expectRevert(IHyperdriveMatchingEngine.AlreadyExpired.selector);
        matchingEngine.matchOrders(
            // long order
            longOrder,
            // short order
            shortOrder,
            // LP amount
            2_000_000e18,
            // add liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // remove liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // fee recipient
            celine,
            true
        );
    }

    /// @dev Ensures that order matching fails when the orders refer to
    ///      different Hyperdrive instances.
    function test_matchOrders_failure_mismatchedHyperdrive() external {
        // Create two orders that can be used for this test. These orders have
        // different Hyperdrive addresses.
        IHyperdriveMatchingEngine.OrderIntent
            memory longOrder = _createOrderIntent(
                alice,
                100_000e18,
                0,
                IHyperdriveMatchingEngine.OrderType.OpenLong
            );
        IHyperdriveMatchingEngine.OrderIntent
            memory shortOrder = _createOrderIntent(
                bob,
                105_000e18,
                type(uint256).max,
                IHyperdriveMatchingEngine.OrderType.OpenShort
            );
        shortOrder.hyperdrive = IHyperdrive(address(0xdeadbeef));

        // Ensure that order matching fails when the orders have different
        // Hyperdrive pools.
        vm.expectRevert(
            IHyperdriveMatchingEngine.MismatchedHyperdrive.selector
        );
        matchingEngine.matchOrders(
            // long order
            longOrder,
            // short order
            shortOrder,
            // LP amount
            2_000_000e18,
            // add liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // remove liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // fee recipient
            celine,
            true
        );
    }

    /// @dev Ensures that order matching fails when either order and/or either
    ///      option have specified `asBase` as false.
    function test_matchOrders_failure_invalidSettlementAsset() external {
        // Create two orders that can be used for this test.
        IHyperdriveMatchingEngine.OrderIntent
            memory longOrder = _createOrderIntent(
                alice,
                100_000e18,
                0,
                IHyperdriveMatchingEngine.OrderType.OpenLong
            );
        IHyperdriveMatchingEngine.OrderIntent
            memory shortOrder = _createOrderIntent(
                bob,
                105_000e18,
                type(uint256).max,
                IHyperdriveMatchingEngine.OrderType.OpenShort
            );

        // Ensure that order matching fails when the long order specifies
        // `asBase` as false.
        longOrder.options.asBase = false;
        vm.expectRevert(
            IHyperdriveMatchingEngine.InvalidSettlementAsset.selector
        );
        matchingEngine.matchOrders(
            // long order
            longOrder,
            // short order
            shortOrder,
            // LP amount
            2_000_000e18,
            // add liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // remove liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // fee recipient
            celine,
            true
        );

        // Ensure that order matching fails when the short order specifies
        // `asBase` as false.
        longOrder.options.asBase = true;
        shortOrder.options.asBase = false;
        vm.expectRevert(
            IHyperdriveMatchingEngine.InvalidSettlementAsset.selector
        );
        matchingEngine.matchOrders(
            // long order
            longOrder,
            // short order
            shortOrder,
            // LP amount
            2_000_000e18,
            // add liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // remove liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // fee recipient
            celine,
            true
        );

        // Ensure that order matching fails when the add liquidity options
        // specify `asBase` as false.
        shortOrder.options.asBase = true;
        vm.expectRevert(
            IHyperdriveMatchingEngine.InvalidSettlementAsset.selector
        );
        matchingEngine.matchOrders(
            // long order
            longOrder,
            // short order
            shortOrder,
            // LP amount
            2_000_000e18,
            // add liquidity options
            IHyperdrive.Options({
                asBase: false,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // remove liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // fee recipient
            celine,
            true
        );

        // Ensure that order matching fails when the remove liquidity options
        // specify `asBase` as false.
        shortOrder.options.asBase = true;
        vm.expectRevert(
            IHyperdriveMatchingEngine.InvalidSettlementAsset.selector
        );
        matchingEngine.matchOrders(
            // long order
            longOrder,
            // short order
            shortOrder,
            // LP amount
            2_000_000e18,
            // add liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // remove liquidity options
            IHyperdrive.Options({
                asBase: false,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // fee recipient
            celine,
            true
        );
    }

    /// @dev Ensures that order matching fails when the price of the short is
    ///      higher than the price of the long.
    function test_matchOrders_failure_invalidMatch() external {
        // Create two orders that can be used for this test. The short has a
        // higher price than the long, so these orders don't cross.
        IHyperdriveMatchingEngine.OrderIntent
            memory longOrder = _createOrderIntent(
                alice,
                100_000e18,
                101_000e18,
                IHyperdriveMatchingEngine.OrderType.OpenLong
            );
        IHyperdriveMatchingEngine.OrderIntent
            memory shortOrder = _createOrderIntent(
                bob,
                101_000e18,
                100e18,
                IHyperdriveMatchingEngine.OrderType.OpenShort
            );

        // Ensure that order matching fails when the orders don't cross.
        vm.expectRevert(IHyperdriveMatchingEngine.InvalidMatch.selector);
        matchingEngine.matchOrders(
            // long order
            longOrder,
            // short order
            shortOrder,
            // LP amount
            2_000_000e18,
            // add liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // remove liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // fee recipient
            celine,
            true
        );
    }

    /// @dev Ensures that order matching fails when either or both of the orders
    ///      have already been cancelled.
    function test_matchOrders_failure_alreadyCancelled() external {
        // Create two orders that can be used for this test.
        IHyperdriveMatchingEngine.OrderIntent
            memory longOrder = _createOrderIntent(
                alice,
                100_000e18,
                0,
                IHyperdriveMatchingEngine.OrderType.OpenLong
            );
        longOrder.signature = _signOrderIntent(longOrder, alicePK);
        IHyperdriveMatchingEngine.OrderIntent
            memory shortOrder = _createOrderIntent(
                bob,
                101_000e18,
                type(uint256).max,
                IHyperdriveMatchingEngine.OrderType.OpenShort
            );
        shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

        // Ensure that order matching fails when the long order was cancelled.
        {
            uint256 snapshotId = vm.snapshot();
            vm.stopPrank();
            vm.startPrank(alice);
            IHyperdriveMatchingEngine.OrderIntent[]
                memory orders = new IHyperdriveMatchingEngine.OrderIntent[](1);
            orders[0] = longOrder;
            matchingEngine.cancelOrders(orders);
            vm.expectRevert(
                IHyperdriveMatchingEngine.AlreadyCancelled.selector
            );
            matchingEngine.matchOrders(
                // long order
                longOrder,
                // short order
                shortOrder,
                // LP amount
                2_000_000e18,
                // add liquidity options
                IHyperdrive.Options({
                    asBase: true,
                    destination: address(matchingEngine),
                    extraData: ""
                }),
                // remove liquidity options
                IHyperdrive.Options({
                    asBase: true,
                    destination: address(matchingEngine),
                    extraData: ""
                }),
                // fee recipient
                celine,
                true
            );
            vm.revertTo(snapshotId);
        }

        // Ensure that order matching fails when the long order was cancelled.
        {
            uint256 snapshotId = vm.snapshot();
            vm.stopPrank();
            vm.startPrank(bob);
            IHyperdriveMatchingEngine.OrderIntent[]
                memory orders = new IHyperdriveMatchingEngine.OrderIntent[](1);
            orders[0] = shortOrder;
            matchingEngine.cancelOrders(orders);
            vm.expectRevert(
                IHyperdriveMatchingEngine.AlreadyCancelled.selector
            );
            matchingEngine.matchOrders(
                // long order
                longOrder,
                // short order
                shortOrder,
                // LP amount
                2_000_000e18,
                // add liquidity options
                IHyperdrive.Options({
                    asBase: true,
                    destination: address(matchingEngine),
                    extraData: ""
                }),
                // remove liquidity options
                IHyperdrive.Options({
                    asBase: true,
                    destination: address(matchingEngine),
                    extraData: ""
                }),
                // fee recipient
                celine,
                true
            );
            vm.revertTo(snapshotId);
        }

        // Ensure that order matching fails when both orders were cancelled.
        {
            uint256 snapshotId = vm.snapshot();
            vm.stopPrank();
            vm.startPrank(alice);
            IHyperdriveMatchingEngine.OrderIntent[]
                memory orders = new IHyperdriveMatchingEngine.OrderIntent[](1);
            orders[0] = longOrder;
            matchingEngine.cancelOrders(orders);
            vm.startPrank(bob);
            orders = new IHyperdriveMatchingEngine.OrderIntent[](1);
            orders[0] = shortOrder;
            matchingEngine.cancelOrders(orders);
            vm.expectRevert(
                IHyperdriveMatchingEngine.AlreadyCancelled.selector
            );
            matchingEngine.matchOrders(
                // long order
                longOrder,
                // short order
                shortOrder,
                // LP amount
                2_000_000e18,
                // add liquidity options
                IHyperdrive.Options({
                    asBase: true,
                    destination: address(matchingEngine),
                    extraData: ""
                }),
                // remove liquidity options
                IHyperdrive.Options({
                    asBase: true,
                    destination: address(matchingEngine),
                    extraData: ""
                }),
                // fee recipient
                celine,
                true
            );
            vm.revertTo(snapshotId);
        }
    }

    /// @dev Ensures that order matching fails when either or both of the orders
    ///      have invalid signatures.
    function test_matchOrders_failure_invalidSignature() external {
        // Create two orders that can be used for this test.
        IHyperdriveMatchingEngine.OrderIntent
            memory longOrder = _createOrderIntent(
                alice,
                100_000e18,
                0,
                IHyperdriveMatchingEngine.OrderType.OpenLong
            );
        longOrder.signature = _signOrderIntent(longOrder, alicePK);
        IHyperdriveMatchingEngine.OrderIntent
            memory shortOrder = _createOrderIntent(
                address(signer),
                101_000e18,
                type(uint256).max,
                IHyperdriveMatchingEngine.OrderType.OpenShort
            );
        shortOrder.signature = hex"deadbeef";

        // Ensure that order matching fails when the long order has an invalid
        // signature.
        longOrder.signature = _signOrderIntent(longOrder, celinePK);
        vm.expectRevert(IHyperdriveMatchingEngine.InvalidSignature.selector);
        matchingEngine.matchOrders(
            // long order
            longOrder,
            // short order
            shortOrder,
            // LP amount
            2_000_000e18,
            // add liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // remove liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // fee recipient
            celine,
            true
        );

        // Ensure that order matching fails when the short order has an invalid
        // signature.
        longOrder.signature = _signOrderIntent(longOrder, alicePK);
        signer.setShouldVerifySignature(false);
        vm.expectRevert(IHyperdriveMatchingEngine.InvalidSignature.selector);
        matchingEngine.matchOrders(
            // long order
            longOrder,
            // short order
            shortOrder,
            // LP amount
            2_000_000e18,
            // add liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // remove liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // fee recipient
            celine,
            true
        );
        signer.setShouldVerifySignature(true);

        // Ensure that order matching fails when both orders have invalid
        // signatures.
        longOrder.signature = _signOrderIntent(longOrder, celinePK);
        signer.setShouldVerifySignature(false);
        vm.expectRevert(IHyperdriveMatchingEngine.InvalidSignature.selector);
        matchingEngine.matchOrders(
            // long order
            longOrder,
            // short order
            shortOrder,
            // LP amount
            2_000_000e18,
            // add liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // remove liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // fee recipient
            celine,
            true
        );
    }

    /// @dev Ensures that order matching fails when either or both of the add or
    ///      remove liquidity options specify a destination other than the
    ///      matching engine.
    function test_matchOrders_failure_invalidDestination() external {
        // Create two orders that can be used for this test.
        IHyperdriveMatchingEngine.OrderIntent
            memory longOrder = _createOrderIntent(
                alice,
                100_000e18,
                0,
                IHyperdriveMatchingEngine.OrderType.OpenLong
            );
        longOrder.signature = _signOrderIntent(longOrder, alicePK);
        IHyperdriveMatchingEngine.OrderIntent
            memory shortOrder = _createOrderIntent(
                bob,
                101_000e18,
                type(uint256).max,
                IHyperdriveMatchingEngine.OrderType.OpenShort
            );
        shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

        // Ensure that order matching fails when the add liquidity options
        // specify a destination other than the matching engine.
        vm.expectRevert(IHyperdriveMatchingEngine.InvalidDestination.selector);
        matchingEngine.matchOrders(
            // long order
            longOrder,
            // short order
            shortOrder,
            // LP amount
            2_000_000e18,
            // add liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(celine),
                extraData: ""
            }),
            // remove liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // fee recipient
            celine,
            true
        );

        // Ensure that order matching fails when the remove liquidity options
        // specify a destination other than the matching engine.
        vm.expectRevert(IHyperdriveMatchingEngine.InvalidDestination.selector);
        matchingEngine.matchOrders(
            // long order
            longOrder,
            // short order
            shortOrder,
            // LP amount
            2_000_000e18,
            // add liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // remove liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(celine),
                extraData: ""
            }),
            // fee recipient
            celine,
            true
        );

        // Ensure that order matching fails when both the add liquidity options
        // and the remove liquidity options specify a destination other than the
        // matching engine.
        vm.expectRevert(IHyperdriveMatchingEngine.InvalidDestination.selector);
        matchingEngine.matchOrders(
            // long order
            longOrder,
            // short order
            shortOrder,
            // LP amount
            2_000_000e18,
            // add liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(celine),
                extraData: ""
            }),
            // remove liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(celine),
                extraData: ""
            }),
            // fee recipient
            celine,
            true
        );
    }

    /// @dev Ensures that orders can be matched and executed with the long first.
    ///      Both traders should receive a realized rate lower than the starting
    ///      rate.
    function test_matchOrders_success_longFirst() external {
        // Create two orders that can be used for this test.
        IHyperdriveMatchingEngine.OrderIntent
            memory longOrder = _createOrderIntent(
                alice,
                100_000e18,
                0,
                IHyperdriveMatchingEngine.OrderType.OpenLong
            );
        longOrder.signature = _signOrderIntent(longOrder, alicePK);
        IHyperdriveMatchingEngine.OrderIntent
            memory shortOrder = _createOrderIntent(
                bob,
                101_000e18,
                101_000e18,
                IHyperdriveMatchingEngine.OrderType.OpenShort
            );
        shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

        // Get some data before the trades are matched.
        uint256 spotRate = hyperdrive.calculateSpotAPR();
        uint256 aliceBaseBalanceBefore = ERC20(hyperdrive.baseToken())
            .balanceOf(alice);
        uint256 aliceLongBalanceBefore = hyperdrive.balanceOf(
            AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.Long,
                hyperdrive.latestCheckpoint()
            ),
            alice
        );
        uint256 bobBaseBalanceBefore = ERC20(hyperdrive.baseToken()).balanceOf(
            bob
        );
        uint256 bobShortBalanceBefore = hyperdrive.balanceOf(
            AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.Short,
                hyperdrive.latestCheckpoint()
            ),
            bob
        );
        uint256 celineBaseBalanceBefore = ERC20(hyperdrive.baseToken())
            .balanceOf(celine);

        // Match the orders.
        matchingEngine.matchOrders(
            // long order
            longOrder,
            // short order
            shortOrder,
            // LP amount
            2_000_000e18,
            // add liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // remove liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // fee recipient
            celine,
            true
        );

        // Ensure that the long received a rate lower than the spot rate.
        {
            uint256 longPaid = aliceBaseBalanceBefore -
                ERC20(hyperdrive.baseToken()).balanceOf(alice);
            uint256 longAmount = hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Long,
                    hyperdrive.latestCheckpoint() +
                        hyperdrive.getPoolConfig().positionDuration
                ),
                alice
            ) - aliceLongBalanceBefore;
            uint256 longFixedRate = HyperdriveUtils
                .calculateAPRFromRealizedPrice(
                    longPaid,
                    longAmount,
                    hyperdrive.getPoolConfig().positionDuration.divDown(
                        365 days
                    )
                );
            assertEq(longPaid, longOrder.amount);
            assertLt(longFixedRate, spotRate);
        }

        // Ensure that the short received a rate lower than the spot rate.
        {
            uint256 shortPaid = bobBaseBalanceBefore -
                ERC20(hyperdrive.baseToken()).balanceOf(bob);
            uint256 shortAmount = hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    hyperdrive.latestCheckpoint() +
                        hyperdrive.getPoolConfig().positionDuration
                ),
                bob
            ) - bobShortBalanceBefore;
            uint256 prepaidInterest = shortAmount.mulDown(
                hyperdrive.getPoolInfo().vaultSharePrice -
                    hyperdrive
                        .getCheckpoint(hyperdrive.latestCheckpoint())
                        .vaultSharePrice
            );
            shortPaid -= prepaidInterest;
            uint256 shortFixedRate = HyperdriveUtils
                .calculateAPRFromRealizedPrice(
                    shortAmount -
                        (shortPaid -
                            shortAmount.mulDown(
                                hyperdrive.getPoolConfig().fees.flat
                            )),
                    shortAmount,
                    hyperdrive.getPoolConfig().positionDuration.divDown(
                        365 days
                    )
                );
            assertEq(shortAmount, shortOrder.amount);
            assertLt(shortFixedRate, spotRate);
        }

        // Ensure that the fee recipient receives some fees.
        assertGt(
            ERC20(hyperdrive.baseToken()).balanceOf(celine),
            celineBaseBalanceBefore
        );
    }

    /// @dev Ensures that orders can be matched and executed with the short first.
    ///      Both traders should receive a realized rate higher than the starting
    ///      rate.
    function test_matchOrders_success_shortFirst() external {
        // Create two orders that can be used for this test.
        IHyperdriveMatchingEngine.OrderIntent
            memory longOrder = _createOrderIntent(
                alice,
                100_000e18,
                0,
                IHyperdriveMatchingEngine.OrderType.OpenLong
            );
        longOrder.signature = _signOrderIntent(longOrder, alicePK);
        IHyperdriveMatchingEngine.OrderIntent
            memory shortOrder = _createOrderIntent(
                bob,
                101_000e18,
                101_000e18,
                IHyperdriveMatchingEngine.OrderType.OpenShort
            );
        shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

        // Get some data before the trades are matched.
        uint256 spotRate = hyperdrive.calculateSpotAPR();
        uint256 aliceBaseBalanceBefore = ERC20(hyperdrive.baseToken())
            .balanceOf(alice);
        uint256 aliceLongBalanceBefore = hyperdrive.balanceOf(
            AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.Long,
                hyperdrive.latestCheckpoint()
            ),
            alice
        );
        uint256 bobBaseBalanceBefore = ERC20(hyperdrive.baseToken()).balanceOf(
            bob
        );
        uint256 bobShortBalanceBefore = hyperdrive.balanceOf(
            AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.Short,
                hyperdrive.latestCheckpoint()
            ),
            bob
        );
        uint256 celineBaseBalanceBefore = ERC20(hyperdrive.baseToken())
            .balanceOf(celine);

        // Match the orders.
        matchingEngine.matchOrders(
            // long order
            longOrder,
            // short order
            shortOrder,
            // LP amount
            2_000_000e18,
            // add liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // remove liquidity options
            IHyperdrive.Options({
                asBase: true,
                destination: address(matchingEngine),
                extraData: ""
            }),
            // fee recipient
            celine,
            false
        );

        // Ensure that the long received a rate lower than the spot rate.
        {
            uint256 longPaid = aliceBaseBalanceBefore -
                ERC20(hyperdrive.baseToken()).balanceOf(alice);
            uint256 longAmount = hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Long,
                    hyperdrive.latestCheckpoint() +
                        hyperdrive.getPoolConfig().positionDuration
                ),
                alice
            ) - aliceLongBalanceBefore;
            uint256 longFixedRate = HyperdriveUtils
                .calculateAPRFromRealizedPrice(
                    longPaid,
                    longAmount,
                    hyperdrive.getPoolConfig().positionDuration.divDown(
                        365 days
                    )
                );
            assertEq(longPaid, longOrder.amount);
            assertGt(longFixedRate, spotRate);
        }

        // Ensure that the short received a rate lower than the spot rate.
        {
            uint256 shortPaid = bobBaseBalanceBefore -
                ERC20(hyperdrive.baseToken()).balanceOf(bob);
            uint256 shortAmount = hyperdrive.balanceOf(
                AssetId.encodeAssetId(
                    AssetId.AssetIdPrefix.Short,
                    hyperdrive.latestCheckpoint() +
                        hyperdrive.getPoolConfig().positionDuration
                ),
                bob
            ) - bobShortBalanceBefore;
            uint256 prepaidInterest = shortAmount.mulDown(
                hyperdrive.getPoolInfo().vaultSharePrice -
                    hyperdrive
                        .getCheckpoint(hyperdrive.latestCheckpoint())
                        .vaultSharePrice
            );
            shortPaid -= prepaidInterest;
            uint256 shortFixedRate = HyperdriveUtils
                .calculateAPRFromRealizedPrice(
                    shortAmount -
                        (shortPaid -
                            shortAmount.mulDown(
                                hyperdrive.getPoolConfig().fees.flat
                            )),
                    shortAmount,
                    hyperdrive.getPoolConfig().positionDuration.divDown(
                        365 days
                    )
                );
            assertEq(shortAmount, shortOrder.amount);
            assertGt(shortFixedRate, spotRate);
        }

        // Ensure that the fee recipient receives some fees.
        assertGt(
            ERC20(hyperdrive.baseToken()).balanceOf(celine),
            celineBaseBalanceBefore
        );
    }

    /// @dev Ensures that `onMorphoFlashLoan` can't be called by an address
    ///      other than Morpho.
    function test_onMorphoFlashLoan_failure_senderNotMorpho() external {
        // Create two orders that can be used for this test.
        IHyperdriveMatchingEngine.OrderIntent
            memory longOrder = _createOrderIntent(
                alice,
                100_000e18,
                0,
                IHyperdriveMatchingEngine.OrderType.OpenLong
            );
        longOrder.signature = _signOrderIntent(longOrder, alicePK);
        IHyperdriveMatchingEngine.OrderIntent
            memory shortOrder = _createOrderIntent(
                bob,
                101_000e18,
                101_000e18,
                IHyperdriveMatchingEngine.OrderType.OpenShort
            );
        shortOrder.signature = _signOrderIntent(shortOrder, bobPK);

        // Alice shouldn't be able to call `onMorphoFlashLoan`.
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(IHyperdriveMatchingEngine.SenderNotMorpho.selector);
        matchingEngine.onMorphoFlashLoan(
            100_000e18,
            abi.encode(
                // long order
                longOrder,
                // short order
                shortOrder,
                // add liquidity options
                IHyperdrive.Options({
                    asBase: true,
                    destination: address(matchingEngine),
                    extraData: ""
                }),
                // remove liquidity options
                IHyperdrive.Options({
                    asBase: true,
                    destination: address(matchingEngine),
                    extraData: ""
                }),
                // fee recipient
                alice,
                // is long first
                false
            )
        );
    }

    /// @dev Creates an unsigned order intent with default parameters.
    /// @param _trader The trader creating the order.
    /// @param _amount The amount that should be traded. This is the base
    ///        deposit when opening a long and the bond deposit when opening a
    ///        short.
    /// @param _slippageGuard The slippage guard for the order. This is
    ///        `minOutput` when opening a long and `maxDeposit` when opening a
    ///        short.
    /// @param _orderType The type of the order. This is either `OpenLong` or
    ///        `OpenShort`.
    function _createOrderIntent(
        address _trader,
        uint256 _amount,
        uint256 _slippageGuard,
        IHyperdriveMatchingEngine.OrderType _orderType
    ) internal returns (IHyperdriveMatchingEngine.OrderIntent memory) {
        salt = keccak256(abi.encode(salt));
        return
            IHyperdriveMatchingEngine.OrderIntent({
                trader: _trader,
                hyperdrive: hyperdrive,
                amount: _amount,
                slippageGuard: _slippageGuard,
                minVaultSharePrice: hyperdrive
                    .getCheckpoint(hyperdrive.latestCheckpoint())
                    .vaultSharePrice,
                options: IHyperdrive.Options({
                    destination: _trader,
                    asBase: true,
                    extraData: ""
                }),
                orderType: _orderType,
                signature: "",
                expiry: block.timestamp + 1 days,
                salt: salt
            });
    }

    /// @dev Signs an order intent with an EOA's private key.
    /// @param _order The order intent to sign.
    /// @param _privateKey The private key to use when signing.
    /// @return The signature.
    function _signOrderIntent(
        IHyperdriveMatchingEngine.OrderIntent memory _order,
        uint256 _privateKey
    ) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            _privateKey,
            matchingEngine.hashOrderIntent(_order)
        );
        return abi.encodePacked(r, s, v);
    }

    /// @dev Ensure that the correct event was emitted when orders were
    ///      cancelled.
    /// @param _trader The trader that cancelled the order.
    /// @param _orders The orders that were cancelled.
    function _verifyCancelOrdersEvent(
        address _trader,
        IHyperdriveMatchingEngine.OrderIntent[] memory _orders
    ) internal {
        VmSafe.Log[] memory logs = vm.getRecordedLogs().filterLogs(
            OrdersCancelled.selector
        );
        assertEq(logs.length, 1);
        VmSafe.Log memory log = logs[0];
        assertEq(address(uint160(uint256(log.topics[1]))), _trader);
        bytes32[] memory orderHashes = abi.decode(log.data, (bytes32[]));
        assertEq(orderHashes.length, _orders.length);
        for (uint256 i = 0; i < orderHashes.length; i++) {
            assertEq(
                orderHashes[i],
                matchingEngine.hashOrderIntent(_orders[i])
            );
        }
    }
}
