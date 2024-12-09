// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { ECDSA } from "openzeppelin/utils/cryptography/ECDSA.sol";
import { EIP712 } from "openzeppelin/utils/cryptography/EIP712.sol";
import { IERC1271 } from "openzeppelin/interfaces/IERC1271.sol";

contract HyperdriveMatchingEngine is EIP712 {
    using ECDSA for bytes32;

    // Order struct that captures all required parameters
    struct Order {
        address trader;          // Address of the trader
        uint256 bondSize;       // Size of trade in bonds
        uint256 price;          // Price/fixed rate to receive
        bool isLong;            // true for long, false for short
        bool isBuy;             // true for buy, false for sell
        bool asBase;            // true for base token, false for vault shares
        uint256 expiry;         // Timestamp when order expires
        address pool;           // Hyperdrive pool address
        bytes signature;        // Order signature
    }

    // Order status tracking
    mapping(bytes32 => uint256) public orderFills;    // Order hash => filled amount
    mapping(bytes32 => bool) public orderCancelled;   // Order hash => cancelled status

    constructor() EIP712("HyperdriveMatchingEngine", "2.0.0") {}

    /// @notice Validates an order's signature and status
    function _validateOrder(Order calldata order) internal view returns (bytes32) {
        bytes32 orderHash = _hashOrder(order);
    
        // Check expiry
        require(block.timestamp <= order.expiry, "Order expired");
    
        // Check if cancelled
        require(!orderCancelled[orderHash], "Order cancelled");
        
        // Verify signature using the more comprehensive verification method
        require(verifySignature(orderHash, order.signature, order.trader), "Invalid signature");

        return orderHash;
    }

    /// @notice Matches two compatible orders
    function matchOrders(
        Order calldata order1,
        Order calldata order2
    ) external returns (uint256 matchedAmount) {
        // Validate both orders
        bytes32 hash1 = _validateOrder(order1);
        bytes32 hash2 = _validateOrder(order2);

        // Verify orders are compatible
        require(_areOrdersCompatible(order1, order2), "Incompatible orders");

        // Calculate matched amount (minimum of remaining amounts)
        uint256 remaining1 = order1.bondSize - orderFills[hash1];
        uint256 remaining2 = order2.bondSize - orderFills[hash2];
        matchedAmount = remaining1 < remaining2 ? remaining1 : remaining2;

        // Update fill amounts
        orderFills[hash1] += matchedAmount;
        orderFills[hash2] += matchedAmount;

        // Calculate total price and execute mint
        uint256 totalPrice = _calculateTotalPrice(order1, order2, matchedAmount);
        
        // Create PairOptions for mint
        IHyperdrive.PairOptions memory options = _createPairOptions(
            order1,
            order2,
            matchedAmount
        );

        // Execute mint through Hyperdrive pool
        IHyperdrive(order1.pool)._mint(
            totalPrice,
            0, // minVaultSharePrice - set appropriately based on requirements
            options
        );
    }

    /// @notice Cancels an order
    function cancelOrder(Order calldata order) external {
        require(msg.sender == order.trader, "Not order owner");
        bytes32 orderHash = _hashOrder(order);
        orderCancelled[orderHash] = true;
    }

    // Helper functions...
    function _hashOrder(Order calldata order) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(
            keccak256("Order(address trader,uint256 bondSize,uint256 price,bool isLong,bool isBuy,bool asBase,uint256 expiry,address pool)"),
            order.trader,
            order.bondSize,
            order.price,
            order.isLong,
            order.isBuy,
            order.asBase,
            order.expiry,
            order.pool
        )));
    }

    /// @notice Verifies a signature for a known signer
    /// @param _hash The EIP-712 hash of the order
    /// @param _signature The signature bytes
    /// @param _signer The expected signer
    /// @return A flag indicating whether signature verification was successful
    function verifySignature(
        bytes32 _hash,
        bytes calldata _signature,
        address _signer
    ) public view returns (bool) {
        // For contracts, use EIP-1271 signatures
        if (_signer.code.length > 0) {
            try IERC1271(_signer).isValidSignature(_hash, _signature) returns (bytes4 magicValue) {
                return magicValue == IERC1271.isValidSignature.selector;
            } catch {
                return false;
            }
        }
    
        // For EOAs, verify the ECDSA signature
        return ECDSA.recover(_hash, _signature) == _signer;
    }

    function _areOrdersCompatible(Order calldata order1, Order calldata order2) internal pure returns (bool) {
        // Implement compatibility logic based on the different matching scenarios
        // from the issue description
        return true; // Placeholder
    }

    function _calculateTotalPrice(
        Order calldata order1,
        Order calldata order2,
        uint256 matchedAmount
    ) internal pure returns (uint256) {
        // Implement price calculation logic
        return 0; // Placeholder
    }

    function _createPairOptions(
        Order calldata order1,
        Order calldata order2,
        uint256 matchedAmount
    ) internal pure returns (IHyperdrive.PairOptions memory) {
        // Create appropriate PairOptions based on the orders
        return IHyperdrive.PairOptions({
            longDestination: address(0), // Set based on orders
            shortDestination: address(0), // Set based on orders
            asBase: true, // Set based on orders
            extraData: "" // Set if needed
        });
    }
}