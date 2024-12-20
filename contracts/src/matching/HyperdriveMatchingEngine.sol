// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { IERC1271 } from "lib/openzeppelin-contracts/contracts/interfaces/IERC1271.sol";
import { ERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { ECDSA } from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import { ReentrancyGuard } from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveMatchingEngine } from "../interfaces/IHyperdriveMatchingEngine.sol";
import { AssetId } from "../libraries/AssetId.sol";
import { HYPERDRIVE_MATCHING_ENGINE_KIND, VERSION } from "../libraries/Constants.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";

/// @title HyperdriveMatchingEngine
/// @notice A matching engine that processes order intents and settles trades on the Hyperdrive AMM
/// @dev This version uses direct Hyperdrive mint/burn functions instead of flash loans
contract HyperdriveMatchingEngine is 
    IHyperdriveMatchingEngine,
    ReentrancyGuard,
    EIP712
{
    using FixedPointMath for uint256;
    using SafeERC20 for ERC20;

    /// @notice The EIP712 typehash of the OrderIntent struct
    bytes32 public constant ORDER_INTENT_TYPEHASH =
        keccak256(
            "OrderIntent(address trader,address counterparty,address feeRecipient,address hyperdrive,uint256 amount,uint256 slippageGuard,uint256 minVaultSharePrice,Options options,uint8 orderType,uint256 expiry,bytes32 salt)"
        );

    /// @notice The EIP712 typehash of the Options struct
    bytes32 public constant OPTIONS_TYPEHASH =
        keccak256("Options(address destination,bool asBase)");

    /// @notice The name of this matching engine
    string public name;

    /// @notice The kind of this matching engine
    string public constant kind = HYPERDRIVE_MATCHING_ENGINE_KIND;

    /// @notice The version of this matching engine
    string public constant version = VERSION;

    /// @notice Mapping to track cancelled orders
    mapping(bytes32 => bool) public isCancelled;

    /// @notice Initializes the matching engine
    /// @param _name The name of this matching engine
    constructor(string memory _name) EIP712(_name, VERSION) {
        name = _name;
    }

    /// @notice Matches a long order with a short order
    /// @param _longOrder The order intent to open a long position
    /// @param _shortOrder The order intent to open a short position
    /// @param _lpAmount Unused in this version, kept for interface compatibility
    /// @param _addLiquidityOptions Unused in this version, kept for interface compatibility
    /// @param _removeLiquidityOptions Unused in this version, kept for interface compatibility
    /// @param _feeRecipient The address that receives any excess fees
    /// @param _isLongFirst Flag indicating whether to execute long or short first
    function matchOrders(
        OrderIntent calldata _longOrder,
        OrderIntent calldata _shortOrder,
        uint256 _lpAmount,
        IHyperdrive.Options calldata _addLiquidityOptions,
        IHyperdrive.Options calldata _removeLiquidityOptions,
        address _feeRecipient,
        bool _isLongFirst
    ) external nonReentrant {
        // Validate orders
        (bytes32 longOrderHash, bytes32 shortOrderHash) = _validateOrders(
            _longOrder,
            _shortOrder,
            _addLiquidityOptions,
            _removeLiquidityOptions,
            _feeRecipient
        );

        // Cancel orders to prevent replay
        isCancelled[longOrderHash] = true;
        isCancelled[shortOrderHash] = true;

        IHyperdrive hyperdrive = _longOrder.hyperdrive;
        ERC20 baseToken = ERC20(hyperdrive.baseToken());

        // Execute orders in specified order
        if (_isLongFirst) {
            _handleLongOrder(hyperdrive, baseToken, _longOrder);
            _handleShortOrder(hyperdrive, baseToken, _shortOrder);
        } else {
            _handleShortOrder(hyperdrive, baseToken, _shortOrder);
            _handleLongOrder(hyperdrive, baseToken, _longOrder);
        }

        emit OrdersMatched(
            hyperdrive,
            longOrderHash,
            shortOrderHash,
            _longOrder.trader,
            _shortOrder.trader
        );
    }

    /// @notice Allows traders to cancel their orders
    /// @param _orders Array of orders to cancel
    function cancelOrders(OrderIntent[] calldata _orders) external nonReentrant {
        bytes32[] memory orderHashes = new bytes32[](_orders.length);
        
        for (uint256 i = 0; i < _orders.length; i++) {
            // Ensure sender is the trader
            if (msg.sender != _orders[i].trader) {
                revert InvalidSender();
            }

            // Verify signature
            bytes32 orderHash = hashOrderIntent(_orders[i]);
            if (!verifySignature(orderHash, _orders[i].signature, msg.sender)) {
                revert InvalidSignature();
            }

            // Cancel the order
            isCancelled[orderHash] = true;
            orderHashes[i] = orderHash;
        }

        emit OrdersCancelled(msg.sender, orderHashes);
    }

    /// @notice Hashes an order intent according to EIP-712
    /// @param _order The order intent to hash
    /// @return The hash of the order intent
    function hashOrderIntent(
        OrderIntent calldata _order
    ) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    ORDER_INTENT_TYPEHASH,
                    _order.trader,
                    _order.counterparty,
                    _order.feeRecipient,
                    address(_order.hyperdrive),
                    _order.amount,
                    _order.slippageGuard,
                    _order.minVaultSharePrice,
                    keccak256(
                        abi.encode(
                            OPTIONS_TYPEHASH,
                            _order.options.destination,
                            _order.options.asBase
                        )
                    ),
                    uint8(_order.orderType),
                    _order.expiry,
                    _order.salt
                )
            )
        );
    }

    /// @notice Verifies a signature for a given signer
    /// @param _hash The EIP-712 hash of the order
    /// @param _signature The signature bytes
    /// @param _signer The expected signer
    /// @return True if signature is valid, false otherwise
    function verifySignature(
        bytes32 _hash,
        bytes calldata _signature,
        address _signer
    ) public view returns (bool) {
        // For contracts, use EIP-1271
        if (_signer.code.length > 0) {
            try IERC1271(_signer).isValidSignature(_hash, _signature) returns (
                bytes4 magicValue
            ) {
                return magicValue == IERC1271.isValidSignature.selector;
            } catch {
                return false;
            }
        }

        // For EOAs, verify ECDSA signature
        return ECDSA.recover(_hash, _signature) == _signer;
    }

    /// @dev Handles the execution of a long order
    /// @param _hyperdrive The Hyperdrive contract
    /// @param _baseToken The base token being traded
    /// @param _order The long order to execute
    function _handleLongOrder(
        IHyperdrive _hyperdrive,
        ERC20 _baseToken,
        OrderIntent memory _order
    ) internal {
        _baseToken.safeTransferFrom(
            _order.trader,
            address(this),
            _order.amount
        );
        
        _baseToken.forceApprove(address(_hyperdrive), _order.amount);
        
        _hyperdrive.openLong(
            _order.amount,
            _order.slippageGuard,
            _order.minVaultSharePrice,
            _order.options
        );
    }

    /// @dev Handles the execution of a short order
    /// @param _hyperdrive The Hyperdrive contract
    /// @param _baseToken The base token being traded
    /// @param _order The short order to execute
    function _handleShortOrder(
        IHyperdrive _hyperdrive,
        ERC20 _baseToken,
        OrderIntent memory _order
    ) internal {
        _baseToken.safeTransferFrom(
            _order.trader,
            address(this),
            _order.slippageGuard
        );
        
        _baseToken.forceApprove(address(_hyperdrive), _order.slippageGuard);
        
        (, uint256 shortPaid) = _hyperdrive.openShort(
            _order.amount,
            _order.slippageGuard,
            _order.minVaultSharePrice,
            _order.options
        );

        // Refund excess collateral if any
        if (_order.slippageGuard > shortPaid) {
            _baseToken.safeTransfer(
                _order.trader,
                _order.slippageGuard - shortPaid
            );
        }
    }

    /// @dev Validates orders before matching
    /// @param _longOrder The long order to validate
    /// @param _shortOrder The short order to validate
    /// @param _addLiquidityOptions The add liquidity options
    /// @param _removeLiquidityOptions The remove liquidity options
    /// @param _feeRecipient The fee recipient address
    /// @return longOrderHash The hash of the long order
    /// @return shortOrderHash The hash of the short order
    function _validateOrders(
        OrderIntent calldata _longOrder,
        OrderIntent calldata _shortOrder,
        IHyperdrive.Options calldata _addLiquidityOptions,
        IHyperdrive.Options calldata _removeLiquidityOptions,
        address _feeRecipient
    ) internal view returns (bytes32 longOrderHash, bytes32 shortOrderHash) {
        // Verify order types
        if (
            _longOrder.orderType != OrderType.OpenLong ||
            _shortOrder.orderType != OrderType.OpenShort
        ) {
            revert InvalidOrderType();
        }

        // Verify counterparties
        if (
            (_longOrder.counterparty != address(0) &&
                _longOrder.counterparty != _shortOrder.trader) ||
            (_shortOrder.counterparty != address(0) &&
                _shortOrder.counterparty != _longOrder.trader)
        ) {
            revert InvalidCounterparty();
        }

        // Verify fee recipients
        if (
            (_longOrder.feeRecipient != address(0) &&
                _longOrder.feeRecipient != _feeRecipient) ||
            (_shortOrder.feeRecipient != address(0) &&
                _shortOrder.feeRecipient != _feeRecipient)
        ) {
            revert InvalidFeeRecipient();
        }

        // Check expiry
        if (
            _longOrder.expiry <= block.timestamp ||
            _shortOrder.expiry <= block.timestamp
        ) {
            revert AlreadyExpired();
        }

        // Verify Hyperdrive instance
        if (_longOrder.hyperdrive != _shortOrder.hyperdrive) {
            revert MismatchedHyperdrive();
        }

        // Verify settlement asset
        if (
            !_longOrder.options.asBase ||
            !_shortOrder.options.asBase ||
            !_addLiquidityOptions.asBase ||
            !_removeLiquidityOptions.asBase
        ) {
            revert InvalidSettlementAsset();
        }

        // Hash orders
        longOrderHash = hashOrderIntent(_longOrder);
        shortOrderHash = hashOrderIntent(_shortOrder);

        // Check if orders are cancelled
        if (isCancelled[longOrderHash] || isCancelled[shortOrderHash]) {
            revert AlreadyCancelled();
        }

        // Verify signatures
        if (
            !verifySignature(
                longOrderHash,
                _longOrder.signature,
                _longOrder.trader
            ) ||
            !verifySignature(
                shortOrderHash,
                _shortOrder.signature,
                _shortOrder.trader
            )
        ) {
            revert InvalidSignature();
        }

        // Verify price matching
        if (
            _longOrder.slippageGuard != 0 &&
            _shortOrder.slippageGuard < _shortOrder.amount &&
            _longOrder.amount.divDown(_longOrder.slippageGuard) <
            (_shortOrder.amount - _shortOrder.slippageGuard).divDown(
                _shortOrder.amount
            )
        ) {
            revert InvalidMatch();
        }

        // Ensure that the destination of the add/remove liquidity options is
        // this contract.
        if (
            _addLiquidityOptions.destination != address(this) ||
            _removeLiquidityOptions.destination != address(this)
        ) {
            revert InvalidDestination();
        }
    }
}