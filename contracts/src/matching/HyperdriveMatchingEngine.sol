// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IMorpho } from "morpho-blue/src/interfaces/IMorpho.sol";
import { FixedPointMath, ONE } from "../libraries/FixedPointMath.sol";

// FIXME: Add this to the interfaces file.
interface IERC1271 {
    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4 magicValue);
}

// FIXME: Document the simplifications that were made.
//
// FIXME: Here is a rough list of things I need to do for this matching engine
//        to get to the MCP stage:
//
// 1. [x] Create the order schema.
// 2. [ ] Perform order validation.
//     - Ensure the orders cross.
//     - Ensure neither order is expired.
//     - Ensure neither order has been filled or cancelled.
//     - To make our lives easier, we should ensure that `asBase` is always true
//       for now. Also check `addLiquidityOptions` and `removeLiquidityOptions`.
//       This will support all of the lending markets that we are targeting.
// 3. [x] Add a function for hashing orders.
// 4. [ ] Add cancels.
// 5. [ ] Support partial fills.
//     - I don't know if this is really possible in the current construction.
//       Iterated fills seem possible, but partially filling an order requires
//       being able to compute the input of one trade with the output of another.
//       We can't do this linearly with Hyperdrive.
// 6. [ ] Make it possible to iterate over the order.
// 7. [ ] Make it possible to execute the short before the long.
// 8. [ ] Add signature support for major wallets like Gnosis Safe.
// 10. [ ] Use custom errors instead of requires with string reverts.
// 11. [ ] Use reentrancy guards.
// 12. [ ] Test this mechanism rigorously.
// 13. [ ] Add an interface.
// 14. [ ] Add name, kind, and version.
// 15. [ ] Create tools that make it easier to solve for the inputs that will
//         function correctly.
// 16. [ ] Clean up the function. Can any logic be encapsulated?
contract HyperdriveMatchingEngine is IMorphoFlashLoanCallback {
    using FixedPointMath for uint256;
    using SafeERC20 for ERC20;

    /// @notice Thrown when an order is already cancelled.
    error AlreadyCancelled();

    /// @notice Thrown when an order is already expired.
    error AlreadyExpired();

    /// @notice Thrown when the order type doesn't match the expected type.
    error InvalidOrderType();

    /// @notice Thrown when orders that don't cross are matched.
    error InvalidMatch();

    /// @notice Thrown when `asBase = false` is used. This implementation is
    ///         opinionated to keep the implementation simple.
    error InvalidSettlementAsset();

    // FIXME: The Options component seems wrong.
    //
    /// @notice The EIP712 typehash of the OrderIntent struct.
    bytes32 public constant ORDER_INTENT_TYPEHASH =
        keccak256(
            "OrderIntent(uint256 amount,uint256 slippageGuard,uint256 minVaultSharePrice,Options options,uint8 orderType,bytes signature,uint256 expiry,bytes32 salt)"
        );

    /// @notice The EIP712 typehash of the Options struct.
    bytes32 public constant OPTIONS_TYPEHASH =
        keccak256("Options(address destination,bool asBase,bytes extraData)");

    /// @notice The EIP712 domain separator.
    bytes32 public immutable domainSeparator;

    /// @notice The morpho market that this matching engine connects to as a
    ///         flash loan provider.
    IMorpho public immutable morpho;

    /// @notice A mapping from order hashes to their cancellation status.
    mapping(bytes32 => bool) public cancels;

    /// @notice Initializes the matching engine.
    /// @param _morpho The Morpho pool.
    constructor(IMorpho _morpho) {
        // Initialize the Morpho immutable.
        morpho = _morpho;

        // Calculate the domain separator.
        domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("HyperdriveMatchingEngine")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    /// @notice The type of an order intent.
    enum OrderType {
        OpenLong,
        OpenShort
    }

    /// @notice The order intent struct that encodes a trader's desire to trade.
    struct OrderIntent {
        uint256 amount;
        uint256 slippageGuard;
        uint256 minVaultSharePrice;
        IHyperdrive.Options options;
        OrderType orderType;
        bytes signature;
        uint256 expiry;
        bytes32 salt;
    }

    // FIXME: Re-architect this before documenting it.
    //
    // FIXME: Rename this.
    //
    /// @notice Executes an OTC trade.
    function matchOrders(
        IHyperdrive _hyperdrive,
        address _long,
        address _short,
        OrderIntent calldata _longOrder,
        OrderIntent calldata _shortOrder,
        uint256 _lpAmount,
        IHyperdrive.Options calldata _addLiquidityOptions,
        IHyperdrive.Options calldata _removeLiquidityOptions
    ) external {
        // Ensure that the long and short orders are the correct type.
        if (
            _longOrder.orderType != OrderType.OpenLong ||
            _shortOrder.orderType != OrderType.OpenShort
        ) {
            revert InvalidType();
        }

        // Ensure that neither order has expired.
        if (
            _longOrder.expiry >= block.timestamp ||
            _shortOrder.expiry >= block.timestamp
        ) {
            revert AlreadyExpired();
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

        // Ensure that the order's cross. We can do this by using their slippage
        // guards to determine a minimum or maximum price.
        //
        // NOTE: Since `asBase` always equals `true`, we can compare these
        // directly without conversion logic.
        if (
            _longOrder.amount.divDown(_longOrder.slippageGuard) >=
            (_shortOrder.amount - _shortOrder.slippageGuard).divDown(
                _shortOrder.amount
            )
        ) {
            revert InvalidMatch();
        }

        // Ensure that neither order has been cancelled.
        bytes32 longOrderHash = _hashOrderIntent(_longOrder);
        bytes32 shortOrderHash = _hashOrderIntent(_longOrder);
        if (cancels[longOrderHash] || cancels[shortOrderHash]) {
            revert AlreadyCancelled();
        }

        // FIXME: Next we should perform signature validation.
        //
        // FIXME: Ensure that we support multiple signature types.

        // FIXME: Validate the add and remove liquidity options.

        // Send off the flash loan call to Morpho. The remaining execution logic
        // will be executed in the `onMorphoFlashLoan` callback.
        address loanToken;
        if (_addLiquidityOptions.asBase) {
            loanToken = _hyperdrive.baseToken();
        } else {
            loanToken = _hyperdrive.vaultSharesToken();
        }
        MORPHO.flashLoan(
            loanToken,
            _lpAmount,
            abi.encode(
                _hyperdrive,
                _long,
                _short,
                _longTrade,
                _shortTrade,
                _lpAmount,
                _addLiquidityOptions,
                _removeLiquidityOptions
            )
        );

        // FIXME: Emit an event.
    }

    // FIXME: Rewrite this function and clean it up. There are a few things we
    // need to think through.
    //
    // 1. [ ] Consolidate the arguments.
    // 2. [ ] Add validation for the orders. We'll also need cancels.
    // 3. [ ] Reduce the complexity of the function. Can we DRY up the logic?
    //
    // FIXME: Document this.
    //
    /// @notice Callback called when a flash loan occurs.
    /// @dev The callback is called only if data is not empty.
    /// @param assets The amount of assets that was flash loaned.
    /// @param data Arbitrary data passed to the `flashLoan` function.
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external {
        // Decode the execution parameters. This encodes the information
        // required to execute the LP, long, and short operations.
        (
            IHyperdrive hyperdrive,
            address long,
            address short,
            Trade memory longTrade,
            Trade memory shortTrade,
            uint256 lpAmount,
            IHyperdrive.Options memory addLiquidityOptions,
            IHyperdrive.Options memory removeLiquidityOptions
        ) = abi.decode(
                data,
                (
                    IHyperdrive,
                    address,
                    address,
                    Trade,
                    Trade,
                    uint256,
                    IHyperdrive.Options,
                    IHyperdrive.Options
                )
            );

        // FIXME: Handle rebasing tokens.
        //
        // Add liquidity to the pool.
        ERC20 addLiquidityToken;
        if (addLiquidityOptions.asBase) {
            addLiquidityToken = ERC20(hyperdrive.baseToken());
        } else {
            addLiquidityToken = ERC20(hyperdrive.vaultSharesToken());
        }
        addLiquidityToken.forceApprove(address(hyperdrive), lpAmount + 1);
        uint256 lpShares = hyperdrive.addLiquidity(
            lpAmount,
            0,
            0,
            type(uint256).max,
            addLiquidityOptions
        );

        // FIXME: Handle rebasing tokens.
        //
        // Open the short and send it to the short trader.
        ERC20 shortAsset;
        if (shortTrade.options.asBase) {
            shortAsset = ERC20(hyperdrive.baseToken());
        } else {
            shortAsset = ERC20(hyperdrive.vaultSharesToken());
        }
        shortAsset.safeTransferFrom(
            short,
            address(this),
            shortTrade.slippageGuard
        );
        shortAsset.forceApprove(
            address(hyperdrive),
            shortTrade.slippageGuard + 1
        );
        (, uint256 shortPaid) = hyperdrive.openShort(
            shortTrade.amount,
            shortTrade.slippageGuard,
            shortTrade.minVaultSharePrice,
            shortTrade.options
        );
        if (shortTrade.slippageGuard > shortPaid) {
            shortAsset.safeTransfer(
                short,
                shortTrade.slippageGuard - shortPaid
            );
        }

        // FIXME: Handle rebasing tokens.
        //
        // Open the long and send it to the long trader.
        ERC20 longAsset;
        if (longTrade.options.asBase) {
            longAsset = ERC20(hyperdrive.baseToken());
        } else {
            longAsset = ERC20(hyperdrive.vaultSharesToken());
        }
        longAsset.safeTransferFrom(long, address(this), longTrade.amount);
        longAsset.forceApprove(address(hyperdrive), longTrade.amount + 1);
        (, uint256 longAmount) = hyperdrive.openLong(
            longTrade.amount,
            longTrade.slippageGuard,
            longTrade.minVaultSharePrice,
            longTrade.options
        );

        // FIXME: Handle the case where we can only add liquidity with base and
        // remove with shares. We'll probably need a zap for this case.
        //
        // Remove liquidity. This will repay the flash loan. We revert if there
        // are any withdrawal shares.
        IHyperdrive hyperdrive_ = hyperdrive; // avoid stack-too-deep
        (uint256 proceeds, uint256 withdrawalShares) = hyperdrive_
            .removeLiquidity(lpShares, 0, removeLiquidityOptions);
        require(withdrawalShares == 0, "Invalid withdrawal shares");

        // FIXME: Send any excess proceeds back to the long.

        // Approve Morpho Blue to take back the assets that were provided.
        ERC20 loanToken;
        if (addLiquidityOptions.asBase) {
            loanToken = ERC20(hyperdrive_.baseToken());
        } else {
            loanToken = ERC20(hyperdrive_.vaultSharesToken());
        }
        loanToken.forceApprove(address(MORPHO), lpAmount);
    }

    // FIXME: Simplify this using openzeppelin.
    //
    /// @dev Hashes an order intent according to EIP-712.
    /// @param _order The order intent to hash.
    /// @return The hash of the order intent.
    function _hashOrderIntent(
        OrderIntent calldata _order
    ) internal view returns (bytes32) {
        // First hash the nested Options struct
        bytes32 optionsHash = keccak256(
            abi.encode(
                OPTIONS_TYPEHASH,
                _order.options.destination,
                _order.options.asBase,
                keccak256(bytes(_order.options.extraData)) // Hash of dynamic bytes
            )
        );

        // Then hash the full OrderIntent struct
        bytes32 orderIntentHash = keccak256(
            abi.encode(
                ORDER_INTENT_TYPEHASH,
                _order.amount,
                _order.slippageGuard,
                _order.minVaultSharePrice,
                optionsHash,
                uint8(_order.orderType), // Enum is encoded as uint8
                keccak256(bytes(_order.signature)), // Hash of dynamic bytes
                _order.expiry,
                _order.salt
            )
        );

        // Return the EIP-712 encoded hash
        return
            keccak256(
                abi.encodePacked("\x19\x01", domainHash, orderIntentHash)
            );
    }

    // FIXME: Simplify this using openzeppelin.
    //
    // FIXME: Revert here instead of returning a boolean.
    //
    // FIXME: Review this.
    //
    /// @dev Validates a signature for an order
    /// @param _hash The EIP-712 hash of the order
    /// @param _signature The signature bytes
    /// @param _signer The expected signer of the order
    /// @return True if signature is valid, false otherwise
    function _validateSignature(
        bytes32 _hash,
        bytes calldata _signature,
        address _signer
    ) internal view returns (bool) {
        // Ensure signature is the correct length for standard signatures.
        if (_signature.length != 65) {
            // If the signature isn't the correct length, try EIP-1271
            // validation for contracts.
            try IERC1271(_signer).isValidSignature(_hash, _signature) returns (
                bytes4 magicValue
            ) {
                return magicValue == EIP1271_MAGIC_VALUE;
            } catch {
                return false;
            }
        }

        // Extract signature parameters.
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            // First 32 bytes stores the length; data starts after that.
            r := calldataload(add(_signature.offset, 0))
            s := calldataload(add(_signature.offset, 32))

            // Last byte is the v value.
            v := byte(0, calldataload(add(_signature.offset, 64)))
        }

        // Ensure s is in lower half of secp256k1 curve's order to prevent
        // signature malleability.
        if (
            uint256(s) >
            0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0
        ) {
            return false;
        }

        // Ensure v is either 27 or 28.
        if (v != 27 && v != 28) {
            return false;
        }

        // Recover signer and compare against the expected signer.
        address recoveredSigner = ecrecover(_hash, v, r, s);

        // If the recovered signer isn't the zero address and the recovered
        // signer is equal to the signer, the signature properly validated.
        return recoveredSigner != address(0) && recoveredSigner == _signer;
    }

    // FIXME: Simplify this using openzeppelin.
    //
    // FIXME: Move this somewhere else since this is public.
    //
    /// @notice Validates an order's signature
    /// @param _order The order to validate
    /// @param _signer The expected signer of the order
    /// @return True if order signature is valid, false otherwise
    function validateOrderSignature(
        OrderIntent calldata _order,
        address _signer
    ) public view returns (bool) {
        bytes32 orderHash = _hashOrderIntent(_order);
        return _validateSignature(orderHash, _order.signature, _signer);
    }
}
