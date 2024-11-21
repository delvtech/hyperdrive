// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IMorpho } from "morpho-blue/src/interfaces/IMorpho.sol";
import { IERC1271 } from "openzeppelin/interfaces/IERC1271.sol";
import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { ECDSA } from "openzeppelin/utils/cryptography/ECDSA.sol";
import { EIP712 } from "openzeppelin/utils/cryptography/EIP712.sol";
import { ReentrancyGuard } from "openzeppelin/utils/ReentrancyGuard.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveMatchingEngine } from "../interfaces/IHyperdriveMatchingEngine.sol";
import { HYPERDRIVE_MATCHING_ENGINE_KIND, VERSION } from "../libraries/Constants.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";

// TODO: Document the simplifications that were made.
//
/// @author DELV
/// @title HyperdriveMatchingEngine
/// @notice A matching engine that processes order intents and settles trades on
///         the Hyperdrive AMM.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract HyperdriveMatchingEngine is
    IHyperdriveMatchingEngine,
    ReentrancyGuard,
    EIP712
{
    using FixedPointMath for uint256;
    using SafeERC20 for ERC20;

    /// @notice The EIP712 typehash of the OrderIntent struct.
    bytes32 public constant ORDER_INTENT_TYPEHASH =
        keccak256(
            "OrderIntent(address hyperdrive,uint256 amount,uint256 slippageGuard,uint256 minVaultSharePrice,Options options,uint8 orderType,uint256 expiry,bytes32 salt)"
        );

    /// @notice The EIP712 typehash of the Options struct.
    /// @dev We exclude extra data from the options hashing since it has no
    ///      effect on execution.
    bytes32 public constant OPTIONS_TYPEHASH =
        keccak256("Options(address destination,bool asBase)");

    /// @notice The name of this matching engine.
    string public name;

    /// @notice The kind of this matching engine.
    string public constant kind = HYPERDRIVE_MATCHING_ENGINE_KIND;

    /// @notice The version of this matching engine.
    string public constant version = VERSION;

    /// @notice The morpho market that this matching engine connects to as a
    ///         flash loan provider.
    IMorpho public immutable morpho;

    /// @notice A mapping from order hashes to their cancellation status.
    mapping(bytes32 => bool) public cancels;

    /// @notice Initializes the matching engine.
    /// @param _name The name of this matching engine.
    /// @param _morpho The Morpho pool.
    constructor(string memory _name, IMorpho _morpho) EIP712(_name, VERSION) {
        name = _name;
        morpho = _morpho;
    }

    /// @notice Allows a trader to cancel a list of their orders.
    /// @param _orders The orders to cancel.
    function cancelOrders(OrderIntent[] calldata _orders) external {
        // Cancel all of the orders in the batch.
        bytes32[] memory orderHashes = new bytes32[](_orders.length);
        for (uint256 i = 0; i < _orders.length; i++) {
            // Ensure that the sender signed each order.
            bytes32 orderHash = hashOrderIntent(_orders[i]);
            if (!verifySignature(orderHash, _orders[i].signature, msg.sender)) {
                revert InvalidSignature();
            }

            // Cancel the order.
            cancels[orderHash] = true;
            orderHashes[i] = orderHash;
        }

        emit OrdersCancelled(msg.sender, orderHashes);
    }

    /// @notice Directly matches a long and a short order. To avoid the need for
    ///         liquidity, this function will open a flash loan on Morpho to
    ///         ensure that the pool is appropriately capitalized.
    /// @dev This function isn't marked as nonReentrant because this contract
    ///      will be reentered when the Morpho flash-loan callback is processed.
    ///      `onMorphoFlashLoan` has been marked as non reentrant to ensure that
    ///      the trading logic can't be reentered.
    /// @param _long The long trader.
    /// @param _short The short trader.
    /// @param _longOrder The order intent to open a long.
    /// @param _shortOrder The order intent to open a short.
    /// @param _lpAmount The amount to flash borrow and LP.
    /// @param _addLiquidityOptions The options used when adding liquidity.
    /// @param _removeLiquidityOptions The options used when removing liquidity.
    /// @param _feeRecipient The address that receives the LP fees from matching
    ///        the trades.
    /// @param _isLongFirst A flag indicating whether the long or short should
    ///        be opened first.
    function matchOrders(
        address _long,
        address _short,
        OrderIntent calldata _longOrder,
        OrderIntent calldata _shortOrder,
        uint256 _lpAmount,
        IHyperdrive.Options calldata _addLiquidityOptions,
        IHyperdrive.Options calldata _removeLiquidityOptions,
        address _feeRecipient,
        bool _isLongFirst
    ) external {
        // Validate the order intents and the add and remove liquidity options
        // in preparation of matching the orders.
        (bytes32 longOrderHash, bytes32 shortOrderHash) = _validateOrders(
            _long,
            _short,
            _longOrder,
            _shortOrder,
            _addLiquidityOptions,
            _removeLiquidityOptions
        );

        // Cancel the orders so that they can't be used again.
        cancels[longOrderHash] = true;
        cancels[shortOrderHash] = true;

        // Send off the flash loan call to Morpho. The remaining execution logic
        // will be executed in the `onMorphoFlashLoan` callback.
        morpho.flashLoan(
            // NOTE: The loan token is always the base token since we require
            // `asBase` to be true.
            _longOrder.hyperdrive.baseToken(),
            _lpAmount,
            abi.encode(
                _long,
                _short,
                _longOrder,
                _shortOrder,
                _addLiquidityOptions,
                _removeLiquidityOptions,
                _feeRecipient,
                _isLongFirst
            )
        );

        // Emit an `OrdersMatched` event.
        emit OrdersMatched(
            _longOrder.hyperdrive,
            longOrderHash,
            shortOrderHash,
            _long,
            _short
        );
    }

    /// @notice Callback called when a flash loan occurs.
    /// @dev The callback is called only if data is not empty.
    /// @param _lpAmount The amount of assets that were flash loaned.
    /// @param _data Arbitrary data passed to the `flashLoan` function.
    function onMorphoFlashLoan(
        uint256 _lpAmount,
        bytes calldata _data
    ) external nonReentrant {
        // Decode the execution parameters. This encodes the information
        // required to execute the LP, long, and short operations.
        (
            address long,
            address short,
            OrderIntent memory longOrder,
            OrderIntent memory shortOrder,
            IHyperdrive.Options memory addLiquidityOptions,
            IHyperdrive.Options memory removeLiquidityOptions,
            address feeRecipient,
            bool isLongFirst
        ) = abi.decode(
                _data,
                (
                    address,
                    address,
                    OrderIntent,
                    OrderIntent,
                    IHyperdrive.Options,
                    IHyperdrive.Options,
                    address,
                    bool
                )
            );

        // Add liquidity to the pool.
        IHyperdrive hyperdrive = longOrder.hyperdrive;
        ERC20 baseToken = ERC20(hyperdrive.baseToken());
        uint256 lpAmount = _lpAmount; // avoid stack-too-deep
        uint256 lpShares = _addLiquidity(
            hyperdrive,
            baseToken,
            lpAmount,
            addLiquidityOptions
        );

        // If the long should be executed first, execute the long and then the
        // short.
        if (isLongFirst) {
            _openLong(hyperdrive, baseToken, long, longOrder);
            _openShort(hyperdrive, baseToken, short, shortOrder);
        }
        // Otherwise, execute the short and then the long.
        else {
            _openShort(hyperdrive, baseToken, short, shortOrder);
            _openLong(hyperdrive, baseToken, long, longOrder);
        }

        // Remove liquidity. This will repay the flash loan. We revert if there
        // are any withdrawal shares.
        (uint256 proceeds, uint256 withdrawalShares) = hyperdrive
            .removeLiquidity(lpShares, 0, removeLiquidityOptions);
        if (withdrawalShares > 0) {
            revert UnexpectedWithdrawalShares();
        }

        // If the proceeds are greater than the LP amount, we send the difference
        // to the fee recipient.
        if (proceeds > lpAmount) {
            baseToken.safeTransfer(feeRecipient, proceeds - lpAmount);
        }

        // Approve Morpho Blue to take back the assets that were provided.
        baseToken.forceApprove(address(morpho), lpAmount);
    }

    /// @notice Hashes an order intent according to EIP-712
    /// @param _order The order intent to hash
    /// @return The hash of the order intent
    function hashOrderIntent(
        OrderIntent calldata _order
    ) public view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        ORDER_INTENT_TYPEHASH,
                        _order.hyperdrive,
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

    /// @notice Verifies a signature for a known signer. Returns a flag
    ///         indicating whether signature verification was successful.
    /// @param _hash The EIP-712 hash of the order.
    /// @param _signature The signature bytes.
    /// @param _signer The expected signer.
    /// @return A flag inidicating whether signature verification was successful.
    function verifySignature(
        bytes32 _hash,
        bytes calldata _signature,
        address _signer
    ) public view returns (bool) {
        // For contracts, we use EIP-1271 signatures.
        if (_signer.code.length > 0) {
            try IERC1271(_signer).isValidSignature(_hash, _signature) returns (
                bytes4 magicValue
            ) {
                if (magicValue != IERC1271.isValidSignature.selector) {
                    return false;
                }
                return true;
            } catch {
                return false;
            }
        }

        // For EOAs, verify the ECDSA signature.
        if (ECDSA.recover(_hash, _signature) != _signer) {
            return false;
        }

        return true;
    }

    /// @dev Adds liquidity to the Hyperdrive pool.
    /// @param _hyperdrive The Hyperdrive pool.
    /// @param _baseToken The base token of the pool.
    /// @param _lpAmount The amount of base to LP.
    /// @param _options The options that configures how the deposit will be
    ///        settled.
    /// @return The amount of LP shares received.
    function _addLiquidity(
        IHyperdrive _hyperdrive,
        ERC20 _baseToken,
        uint256 _lpAmount,
        IHyperdrive.Options memory _options
    ) internal returns (uint256) {
        _baseToken.forceApprove(address(_hyperdrive), _lpAmount + 1);
        return
            _hyperdrive.addLiquidity(
                _lpAmount,
                0,
                0,
                type(uint256).max,
                _options
            );
    }

    /// @dev Opens a long position in the Hyperdrive pool.
    /// @param _hyperdrive The Hyperdrive pool.
    /// @param _baseToken The base token of the pool.
    /// @param _trader The address of the trader opening the long.
    /// @param _order The order containing the trade parameters.
    function _openLong(
        IHyperdrive _hyperdrive,
        ERC20 _baseToken,
        address _trader,
        OrderIntent memory _order
    ) internal {
        _baseToken.safeTransferFrom(_trader, address(this), _order.amount);
        _baseToken.forceApprove(address(_hyperdrive), _order.amount + 1);
        _hyperdrive.openLong(
            _order.amount,
            _order.slippageGuard,
            _order.minVaultSharePrice,
            _order.options
        );
    }

    /// @dev Opens a short position in the Hyperdrive pool.
    /// @param _hyperdrive The Hyperdrive pool.
    /// @param _baseToken The base token of the pool.
    /// @param _trader The address of the trader opening the short.
    /// @param _order The order containing the trade parameters.
    function _openShort(
        IHyperdrive _hyperdrive,
        ERC20 _baseToken,
        address _trader,
        OrderIntent memory _order
    ) internal {
        _baseToken.safeTransferFrom(
            _trader,
            address(this),
            _order.slippageGuard
        );
        _baseToken.forceApprove(address(_hyperdrive), _order.slippageGuard + 1);
        (, uint256 shortPaid) = _hyperdrive.openShort(
            _order.amount,
            _order.slippageGuard,
            _order.minVaultSharePrice,
            _order.options
        );
        if (_order.slippageGuard > shortPaid) {
            _baseToken.safeTransfer(_trader, _order.slippageGuard - shortPaid);
        }
    }

    /// @dev Validates orders and returns their hashes.
    /// @param _long The long trader.
    /// @param _short The short trader.
    /// @param _longOrder The order intent to open a long.
    /// @param _shortOrder The order intent to open a short.
    /// @param _addLiquidityOptions The options used when adding liquidity.
    /// @param _removeLiquidityOptions The options used when removing liquidity.
    /// @return longOrderHash The hash of the long order.
    /// @return shortOrderHash The hash of the short order.
    function _validateOrders(
        address _long,
        address _short,
        OrderIntent calldata _longOrder,
        OrderIntent calldata _shortOrder,
        IHyperdrive.Options calldata _addLiquidityOptions,
        IHyperdrive.Options calldata _removeLiquidityOptions
    ) internal view returns (bytes32 longOrderHash, bytes32 shortOrderHash) {
        // Ensure that the long and short orders are the correct type.
        if (
            _longOrder.orderType != OrderType.OpenLong ||
            _shortOrder.orderType != OrderType.OpenShort
        ) {
            revert InvalidOrderType();
        }

        // Ensure that neither order has expired.
        if (
            _longOrder.expiry < block.timestamp ||
            _shortOrder.expiry < block.timestamp
        ) {
            revert AlreadyExpired();
        }

        // Ensure that both orders refer to the same Hyperdrive pool.
        if (_longOrder.hyperdrive != _shortOrder.hyperdrive) {
            revert MismatchedHyperdrive();
        }

        // Ensure that all of the transactions should be settled with base.
        if (
            !_longOrder.options.asBase ||
            !_shortOrder.options.asBase ||
            !_addLiquidityOptions.asBase ||
            !_removeLiquidityOptions.asBase
        ) {
            revert InvalidSettlementAsset();
        }

        // Ensure that the order's cross. We can calculate a worst-case price
        // for the long and short using the `amount` and `slippageGuard` fields.
        // In order for the orders to cross, the price of the long should be
        // equal to or higher than the price of the short. This implies that the
        // long is willing to buy bonds at a price equal or higher than the
        // short is selling bonds, which ensures that the trade is valid.
        if (
            _longOrder.amount.divDown(_longOrder.slippageGuard) <=
            (_shortOrder.amount - _shortOrder.slippageGuard).divDown(
                _shortOrder.amount
            )
        ) {
            revert InvalidMatch();
        }

        // Hash both orders
        longOrderHash = hashOrderIntent(_longOrder);
        shortOrderHash = hashOrderIntent(_shortOrder);

        // Ensure that neither order has been cancelled.
        if (cancels[longOrderHash] || cancels[shortOrderHash]) {
            revert AlreadyCancelled();
        }

        // Ensure that the order intents were signed correctly.
        if (
            !verifySignature(longOrderHash, _longOrder.signature, _long) ||
            !verifySignature(shortOrderHash, _shortOrder.signature, _short)
        ) {
            revert InvalidSignature();
        }

        // Ensure that the destination of the add/remove liquidity options is this contract.
        if (
            _addLiquidityOptions.destination != address(this) ||
            _removeLiquidityOptions.destination != address(this)
        ) {
            revert InvalidDestination();
        }
    }
}
