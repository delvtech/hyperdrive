// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";

/// @title IHyperdriveMatchingEngine
/// @notice Interface for the Hyperdrive matching engine.
interface IHyperdriveMatchingEngineV2 {
    /// @notice Thrown when an order is already cancelled.
    error AlreadyCancelled();

    /// @notice Thrown when an order is already expired.
    error AlreadyExpired();

    /// @notice Thrown when the counterparty doesn't match the counterparty
    ///         signed into the order.
    error InvalidCounterparty();

    /// @notice Thrown when the destination for the add or remove liquidity
    ///         options isn't configured to this contract.
    error InvalidDestination();

    /// @notice Thrown when the fee recipient doesn't match the fee recipient
    ///         signed into the order.
    error InvalidFeeRecipient();

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

    /// @notice Thrown when the pool config is invalid.
    error InvalidPoolConfig();
    
    /// @notice Thrown when the bond match amount is zero.
    error NoBondMatchAmount();

    /// @notice Thrown when the used fund amount is greater than the order specified.
    error InvalidFundAmount();

    /// @notice Thrown when the maturity time is not within the range.
    error InvalidMaturityTime();

    /// @notice Thrown when the funding amount is insufficient to cover the cost.
    error InsufficientFunding();

    /// @notice Thrown when the order combination is invalid.
    error InvalidOrderCombination();

    /// @notice Emitted when orders are cancelled.
    /// @param trader The address of the trader who cancelled the orders.
    /// @param orderHashes The hashes of the cancelled orders.
    event OrdersCancelled(address indexed trader, bytes32[] orderHashes);

    /// @notice Emitted when the amount of funds used for an order is updated.
    /// @param orderHash The hash of the order.
    /// @param amountUsed The new total amount of funds used.
    event OrderFundAmountUsedUpdated(bytes32 indexed orderHash, uint256 amountUsed);

    /// @notice Emitted when the amount of bonds used for an order is updated.
    /// @param orderHash The hash of the order.
    /// @param amountUsed The new total amount of bonds used.
    event OrderBondAmountUsedUpdated(bytes32 indexed orderHash, uint256 amountUsed);

    /// @notice Emitted when orders are matched.
    /// @param hyperdrive The Hyperdrive contract where the trade occurred.
    /// @param order1Hash The hash of the first order.
    /// @param order2Hash The hash of the second order.
    /// @param order1Trader The trader of the first order.
    /// @param order2Trader The trader of the second order.
    event OrdersMatched(
        IHyperdrive indexed hyperdrive,
        bytes32 indexed order1Hash,
        bytes32 indexed order2Hash,
        address order1Trader,
        address order2Trader
    );

    /// @notice The type of an order intent.
    enum OrderType {
        OpenLong,
        OpenShort,
        CloseLong,
        CloseShort
    }

    /// @notice The order intent struct that encodes a trader's desire to trade.
    /// @dev All monetary values use the same decimals as the base token.
    struct OrderIntent {
        /// @dev The trader address that will be charged when orders are matched.
        address trader;
        /// @dev The counterparty of the trade. If left as zero, the validation
        ///      is skipped.
        address counterparty;
        /// @dev The fee recipient of the trade. This is the address that will
        ///      receive any excess trading fees on the match. If left as zero,
        ///      the validation is skipped.
        address feeRecipient;
        /// @dev The Hyperdrive address where the trade will be executed.
        IHyperdrive hyperdrive;
        /// @dev The amount to be used in the trade. In the case of `OpenLong` or 
        ///      `OpenShort`, this is the amount of funds to deposit; and in the 
        ///      case of `CloseLong` or `CloseShort`, this is the min amount of 
        ///      funds to receive.
        uint256 fundAmount;
        /// @dev The minimum output amount expected from the trade. In the case of
        ///      `OpenLong` or `OpenShort`, this is the min amount of bonds to 
        ///      receive; and in the case of `CloseLong` or `CloseShort`, this is 
        ///      the amount of bonds to close.
        uint256 bondAmount;
        /// @dev The minimum vault share price. This protects traders against
        ///      the sudden accrual of negative interest in a yield source.
        uint256 minVaultSharePrice;
        /// @dev The options that configure how the trade will be settled.
        ///      `asBase` is required to be true, the `destination` is the
        ///      address that receives the long or short position that is
        ///      purchased, and the extra data is configured for the yield
        ///      source that is being used. Since the extra data isn't included
        ///      in the order's hash, it can be updated between the order being
        ///      signed and executed. This is helpful for applications like DFB
        ///      that rely on the extra data field to record metadata in events.
        IHyperdrive.Options options;
        /// @dev The type of the order. Legal values are `OpenLong`, `OpenShort`,
        ///      `CloseLong`, or `CloseShort`.
        OrderType orderType;

        /// @dev The minimum and maximum maturity time for the order.
        ///      For `OpenLong` or `OpenShort` orders where the `onlyNewPositions`
        ///      is false, these values are checked for match validation.
        ///      For `CloseLong` or `CloseShort` orders, these values are ignored
        ///      and will not be checked during match; however, the general order
        ///      validation will still check the values to be reasonable.
        uint256 minMaturityTime;
        uint256 maxMaturityTime;

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

    /// @notice Get the buffer amount used for cost calculations.
    /// @return The buffer amount.
    function TOKEN_AMOUNT_BUFFER() external view returns (uint256);

    /// @notice Returns whether or not an order has been cancelled.
    /// @param orderHash The hash of the order.
    /// @return True if the order was cancelled and false otherwise.
    function isCancelled(bytes32 orderHash) external view returns (bool);

    /// @notice Get the amount of bonds used for a specific order.
    /// @param orderHash The hash of the order.
    /// @return The amount of bonds used.
    function orderBondAmountUsed(bytes32 orderHash) external view returns (uint256);

    /// @notice Get the amount of funds used for a specific order.
    /// @param orderHash The hash of the order.
    /// @return The amount of funds used.
    function orderFundAmountUsed(bytes32 orderHash) external view returns (uint256);

    /// @notice Get the EIP712 typehash for the
    ///         `IHyperdriveMatchingEngine.OrderIntent` struct.
    /// @return The typehash.
    function ORDER_INTENT_TYPEHASH() external view returns (bytes32);

    /// @notice Get the EIP712 typehash for the `IHyperdrive.Options` struct.
    /// @return The typehash.
    function OPTIONS_TYPEHASH() external view returns (bytes32);

    /// @notice Allows a trader to cancel a list of their orders.
    /// @param _orders The orders to cancel.
    function cancelOrders(OrderIntent[] calldata _orders) external;

    /// @notice Directly matches a long and a short order using a flash loan for
    ///         liquidity.
    /// @param _order1 The order intent to open a long.
    /// @param _order2 The order intent to open a short.
    /// @param _surplusRecipient The address that receives the surplus funds from
    ///        matching the trades.
    function matchOrders(
        OrderIntent calldata _order1,
        OrderIntent calldata _order2,
        address _surplusRecipient
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
