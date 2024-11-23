// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IMorpho } from "morpho-blue/src/interfaces/IMorpho.sol";
import { IMorphoFlashLoanCallback } from "morpho-blue/src/interfaces/IMorphoCallbacks.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";

/// @title IHyperdriveMatchingEngine
/// @notice Interface for the Hyperdrive matching engine.
interface IHyperdriveMatchingEngine is IMorphoFlashLoanCallback {
    /// @notice Thrown when an order is already cancelled.
    error AlreadyCancelled();

    /// @notice Thrown when an order is already expired.
    error AlreadyExpired();

    /// @notice Thrown when the destination for the add or remove liquidity
    ///         options isn't configured to this contract.
    error InvalidDestination();

    /// @notice Thrown when orders that don't cross are matched.
    error InvalidMatch();

    /// @notice Thrown when the order type doesn't match the expected type.
    error InvalidOrderType();

    /// @notice Thrown when an address that didn't create an order tries to
    ///         cancel it.
    error InvalidSender();

    /// @notice Thrown when `asBase = false` is used. This implementation is
    ///         opinionated to keep the implementation simple.
    error InvalidSettlementAsset();

    /// @notice Thrown when the signature for an order intent doesn't recover to
    ///         the expected signer address.
    error InvalidSignature();

    /// @notice Thrown when the long and short orders don't refer to the same
    ///         Hyperdrive instance.
    error MismatchedHyperdrive();

    /// @notice Emitted when orders are cancelled
    event OrdersCancelled(address indexed trader, bytes32[] orderHashes);

    /// @notice Emitted when orders are matched
    event OrdersMatched(
        IHyperdrive indexed hyperdrive,
        bytes32 indexed longOrderHash,
        bytes32 indexed shortOrderHash,
        address long,
        address short
    );

    /// @notice The type of an order intent.
    enum OrderType {
        OpenLong,
        OpenShort
    }

    /// @notice The order intent struct that encodes a trader's desire to trade.
    struct OrderIntent {
        /// @dev The trader address that will be charged when orders are matched.
        address trader;
        /// @dev The Hyperdrive address where the trade will be executed.
        IHyperdrive hyperdrive;
        /// @dev The amount to be used in the trade. In the case of `OpenLong`,
        ///      this is the amount of base to deposit, and in the case of
        ///      `OpenShort`, this is the amount of bonds to short.
        uint256 amount;
        /// @dev The slippage guard to be used in the trade. In the case of
        ///      `OpenLong`, this is the minimum output in bonds, and in the
        ///      case of `OpenShort`, this is the maximum deposit in base.
        uint256 slippageGuard;
        /// @dev The minimum vault share price. This protects traders against
        ///      the sudden accrual of negative interest in a yield source.
        uint256 minVaultSharePrice;
        /// @dev The options that configure how the trade will be settled.
        ///      `asBase` is required to be true, the `destination` is the
        ///      address that receives the long or short position that is
        ///      purchased, and the extra data is configured for the yield
        ///      source that is being used.
        IHyperdrive.Options options;
        /// @dev The type of the order. This is either `OpenLong` or `OpenShort`.
        OrderType orderType;
        /// @dev The signature that demonstrates the source's intent to complete
        ///      the trade.
        bytes signature;
        /// @dev The order's expiry timestamp. At or after this timestamp, the
        ///      order can't be filled.
        uint256 expiry;
        /// @dev The order's salt. This introduces some randomness which ensures
        ///      that duplicate orders don't collide.
        bytes32 salt;
    }

    /// @notice Get the name of this matching engine.
    /// @return The name string.
    function name() external view returns (string memory);

    /// @notice Get the kind of this matching engine.
    /// @return The kind string.
    function kind() external view returns (string memory);

    /// @notice Get the version of this matching engine.
    /// @return The version string.
    function version() external view returns (string memory);

    /// @notice Get the Morpho flash loan provider.
    /// @return The Morpho contract address.
    function morpho() external view returns (IMorpho);

    /// @notice Check if an order has been cancelled.
    /// @param orderHash The hash of the order to check.
    /// @return True if the order was cancelled.
    function cancels(bytes32 orderHash) external view returns (bool);

    /// @notice Get the EIP712 typehash for the OrderIntent struct.
    /// @return The typehash.
    function ORDER_INTENT_TYPEHASH() external view returns (bytes32);

    /// @notice Get the EIP712 typehash for the Options struct.
    /// @return The typehash.
    function OPTIONS_TYPEHASH() external view returns (bytes32);

    /// @notice Allows a trader to cancel a list of their orders.
    /// @param _orders The orders to cancel.
    function cancelOrders(OrderIntent[] calldata _orders) external;

    /// @notice Directly matches a long and a short order using a flash loan for
    ///         liquidity.
    /// @param _longOrder The order intent to open a long.
    /// @param _shortOrder The order intent to open a short.
    /// @param _lpAmount The amount to flash borrow and LP.
    /// @param _addLiquidityOptions The options used when adding liquidity.
    /// @param _removeLiquidityOptions The options used when removing liquidity.
    /// @param _feeRecipient The address that receives the LP fees from matching
    ///        the trades.
    /// @param _isLongFirst A flag indicating whether the long or short should be
    ///        opened first.
    function matchOrders(
        OrderIntent calldata _longOrder,
        OrderIntent calldata _shortOrder,
        uint256 _lpAmount,
        IHyperdrive.Options calldata _addLiquidityOptions,
        IHyperdrive.Options calldata _removeLiquidityOptions,
        address _feeRecipient,
        bool _isLongFirst
    ) external;

    /// @notice Hashes an order intent according to EIP-712.
    /// @param _order The order intent to hash.
    /// @return The hash of the order intent.
    function hashOrderIntent(
        OrderIntent calldata _order
    ) external view returns (bytes32);

    /// @notice Verifies a signature for a known signer.
    /// @param _hash The EIP-712 hash of the order.
    /// @param _signature The signature bytes.
    /// @param _signer The expected signer.
    /// @return True if signature is valid, false otherwise.
    function verifySignature(
        bytes32 _hash,
        bytes calldata _signature,
        address _signer
    ) external view returns (bool);
}
