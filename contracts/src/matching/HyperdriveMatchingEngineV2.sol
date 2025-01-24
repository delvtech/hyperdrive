// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { IERC1271 } from "lib/openzeppelin-contracts/contracts/interfaces/IERC1271.sol";
import { ERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { ECDSA } from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import { ReentrancyGuard } from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveMatchingEngineV2 } from "../interfaces/IHyperdriveMatchingEngineV2.sol";
import { AssetId } from "../libraries/AssetId.sol";
import { HYPERDRIVE_MATCHING_ENGINE_KIND, VERSION } from "../libraries/Constants.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../libraries/HyperdriveMath.sol";

/// @title HyperdriveMatchingEngine
/// @notice A matching engine that processes order intents and settles trades on the Hyperdrive AMM
/// @dev This version uses direct Hyperdrive mint/burn functions instead of flash loans
contract HyperdriveMatchingEngineV2 is 
    IHyperdriveMatchingEngineV2,
    ReentrancyGuard,
    EIP712
{
    using FixedPointMath for uint256;
    using SafeERC20 for ERC20;

    /// @notice The EIP712 typehash of the OrderIntent struct
    bytes32 public constant ORDER_INTENT_TYPEHASH =
        keccak256(
            "OrderIntent(address trader,address counterparty,address feeRecipient,address hyperdrive,uint256 amount,uint256 slippageGuard,uint256 minVaultSharePrice,Options options,uint8 orderType,uint256 minMaturityTime,uint256 maxMaturityTime,uint256 expiry,bytes32 salt)"
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

    /// @notice The buffer amount used for cost related calculations
    uint256 public constant TOKEN_AMOUNT_BUFFER = 10;

    /// @notice Mapping to track cancelled orders
    mapping(bytes32 => bool) public isCancelled;

    /// @notice Mapping to track the bond amount used for each order.
    mapping(bytes32 => uint256) public orderBondAmountUsed;

    /// @notice Mapping to track the amount of base used for each order.
    mapping(bytes32 => uint256) public orderFundAmountUsed;

    /// @notice Initializes the matching engine
    /// @param _name The name of this matching engine
    constructor(string memory _name) EIP712(_name, VERSION) {
        name = _name;
    }

    function matchOrders(
        OrderIntent calldata _order1,
        OrderIntent calldata _order2,
        address _surplusRecipient
    ) external nonReentrant {
        // Validate orders
        (bytes32 order1Hash, bytes32 order2Hash) = _validateOrders(
            _order1, 
            _order2
        );

        // Cancel orders to prevent replay
        // isCancelled[order1Hash] = true;
        // isCancelled[order2Hash] = true;

        IHyperdrive hyperdrive = _order1.hyperdrive;
        ERC20 baseToken = ERC20(hyperdrive.baseToken());

        // Calculate matching amount
        uint256 bondMatchAmount = _calculateBondMatchAmount(_order1, _order2, order1Hash, order2Hash);

        // Handle different order type combinations
        if (_order1.orderType == OrderType.OpenLong && _order2.orderType == OrderType.OpenShort) {
            // Case 1: Long + Short creation using mint()

            // Get necessary pool parameters
            (uint256 checkpointDuration, 
             uint256 positionDuration, 
             uint256 flatFee, 
             uint256 governanceLPFee) = _getHyperdriveDurationsAndFees(hyperdrive);
            
            uint256 latestCheckpoint = _latestCheckpoint(checkpointDuration);
            uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;

            // Calculate the amount of base tokens to transfer based on the bondMatchAmount
            uint256 openVaultSharePrice = hyperdrive.getCheckpoint(latestCheckpoint).vaultSharePrice;
            if (openVaultSharePrice == 0) {
                openVaultSharePrice = vaultSharePrice;
            }

            uint256 baseTokenAmountOrder1 = order1.fundAmount.mulDivDown(bondMatchAmount, order1.bondAmount);
            uint256 baseTokenAmountOrder2 = order2.fundAmount.mulDivDown(bondMatchAmount, order2.bondAmount);

            // Get the sufficient funding amount to mint the bonds.
            uint256 cost = bondMatchAmount.mulDivDown(
                vaultSharePrice.max(openVaultSharePrice), 
                openVaultSharePrice) + 
                bondMatchAmount.mulUp(flatFee) +
                2 * bondMatchAmount.mulUp(flatFee).mulDown(governanceLPFee);

            // Update order fund amount used
            orderFundAmountUsed[order1Hash] += baseTokenAmountOrder1;
            orderFundAmountUsed[order2Hash] += baseTokenAmountOrder2;

            if (orderFundAmountUsed[order1Hash] > order1.fundAmount || 
                orderFundAmountUsed[order2Hash] > order2.fundAmount) {
                revert InvalidFundAmount();
            }
            emit OrderFundAmountUsedUpdated(order1Hash, orderFundAmountUsed[order1Hash]);
            emit OrderFundAmountUsedUpdated(order2Hash, orderFundAmountUsed[order2Hash]);

            // Calculate the maturity time of newly minted positions
            
            uint256 maturityTime = latestCheckpoint + positionDuration;

            // Check if the maturity time is within the range
            if (maturityTime < _order1.minMaturityTime || maturityTime > _order1.maxMaturityTime ||
                maturityTime < _order2.minMaturityTime || maturityTime > _order2.maxMaturityTime) {
                revert InvalidMaturityTime();
            }


            uint256 bondAmount = _handleMint(
                _order1, 
                _order2, 
                baseTokenAmountOrder1, 
                baseTokenAmountOrder2,
                cost, 
                bondMatchAmount, 
                baseToken, 
                hyperdrive);
            
            // Update order bond amount used
            orderBondAmountUsed[order1Hash] += bondAmount;
            orderBondAmountUsed[order2Hash] += bondAmount;
            emit OrderBondAmountUsedUpdated(order1Hash, orderBondAmountUsed[order1Hash]);
            emit OrderBondAmountUsedUpdated(order2Hash, orderBondAmountUsed[order2Hash]);

            // Mark fully executed orders as cancelled 
            if (orderBondAmountUsed[order1Hash] >= _order1.bondAmount || orderFundAmountUsed[order1Hash] >= _order1.fundAmount) {
                isCancelled[order1Hash] = true;
            }
            if (orderBondAmountUsed[order2Hash] >= _order2.bondAmount || orderFundAmountUsed[order2Hash] >= _order2.fundAmount) {
                isCancelled[order2Hash] = true;
            }

            // Transfer the remaining base tokens back to the surplus recipient
            baseToken.safeTransfer(
                _surplusRecipient,
                baseToken.balanceOf(address(this))
            );
        } 


        //TODOs
        else if (_order1.orderType == OrderType.CloseLong && _order2.orderType == OrderType.CloseShort) {
            // Case 2: Long + Short closing using burn()
            _handleBurn();
        }
        else if (_order1.orderType == OrderType.OpenLong && _order2.orderType == OrderType.CloseLong) {
            // Case 3: Long transfer between traders
            _handleLongTransfer();
        }
        else if (_order1.orderType == OrderType.OpenShort && _order2.orderType == OrderType.CloseShort) {
            // Case 4: Short transfer between traders
            _handleShortTransfer();
        }
        else {
            revert InvalidOrderCombination();
        }

        emit OrdersMatched(
            hyperdrive,
            order1Hash,
            order2Hash,
            _order1.trader,
            _order2.trader
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
                    _order.minMaturityTime,
                    _order.maxMaturityTime,
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

    /// @dev Validates orders before matching
    /// @param _longOrder The long order to validate
    /// @param _shortOrder The short order to validate
    /// @param _addLiquidityOptions The add liquidity options
    /// @param _removeLiquidityOptions The remove liquidity options
    /// @param _feeRecipient The fee recipient address
    /// @return longOrderHash The hash of the long order
    /// @return shortOrderHash The hash of the short order
    function _validateOrders(
        OrderIntent calldata _order1,
        OrderIntent calldata _order2
    ) internal view returns (bytes32 order1Hash, bytes32 order2Hash) {
        

        // Verify counterparties
        if (
            (_order1.counterparty != address(0) &&
                _order1.counterparty != _order2.trader) ||
            (_order2.counterparty != address(0) &&
                _order2.counterparty != _order1.trader)
        ) {
            revert InvalidCounterparty();
        }

        // // Verify fee recipients
        // if (
        //     (_order1.feeRecipient != address(0) &&
        //         _order1.feeRecipient != _feeRecipient) ||
        //     (_order2.feeRecipient != address(0) &&
        //         _order2.feeRecipient != _feeRecipient)
        // ) {
        //     revert InvalidFeeRecipient();
        // }

        // Check expiry
        if (
            _order1.expiry <= block.timestamp ||
            _order2.expiry <= block.timestamp
        ) {
            revert AlreadyExpired();
        }

        // Verify Hyperdrive instance
        if (_order1.hyperdrive != _order2.hyperdrive) {
            revert MismatchedHyperdrive();
        }

        // Verify settlement asset
        if (
            !_order1.options.asBase ||
            !_order2.options.asBase
        ) {
            revert InvalidSettlementAsset();
        }

        // Verify valid maturity time
        if (_order1.minMaturityTime > _order1.maxMaturityTime || 
            _order2.minMaturityTime > _order2.maxMaturityTime 
            ) {
            revert InvalidMaturityTime();
        }

        // Hash orders
        order1Hash = hashOrderIntent(_order1);
        order2Hash = hashOrderIntent(_order2);

        // Check if orders are cancelled
        if (isCancelled[order1Hash] || isCancelled[order2Hash]) {
            revert AlreadyCancelled();
        }


        // Verify signatures
        if (
            !verifySignature(
                order1Hash,
                _order1.signature,
                _order1.trader
            ) ||
            !verifySignature(
                order2Hash,
                _order2.signature,
                _order2.trader
            )
        ) {
            revert InvalidSignature();
        }

        // // Verify price matching
        // if (
        //     _order1.slippageGuard != 0 &&
        //     _order2.slippageGuard < _order2.amount &&
        //     _order1.amount.divDown(_order1.slippageGuard) <
        //     (_order2.amount - _order2.slippageGuard).divDown(
        //         _order2.amount
        //     )
        // ) {
        //     revert InvalidMatch();
        // }

    }

    function _calculateBondMatchAmount(
        OrderIntent calldata _order1,
        OrderIntent calldata _order2,
        bytes32 _order1Hash,
        bytes32 _order2Hash
    ) internal pure returns (
        uint256 bondMatchAmount
    ) {
        uint256 order1BondAmountUsed = orderBondAmountUsed[_order1Hash];
        uint256 order2BondAmountUsed = orderBondAmountUsed[_order2Hash];

        if (order1BondAmountUsed >= _order1.bondAmount || order2BondAmountUsed >= _order2.bondAmount) {
            revert NoBondMatchAmount();
        }

        uint256 _order1BondAmount = _order1.bondAmount - order1BondAmountUsed;
        uint256 _order2BondAmount = _order2.bondAmount - order2BondAmountUsed;
            
        bondMatchAmount = _order1BondAmount.min(order2BondAmount);
    }

    function _handleMint(
        OrderIntent calldata _longOrder,
        OrderIntent calldata _shortOrder,
        uint256 _baseTokenAmountLongOrder,
        uint256 _baseTokenAmountShortOrder,
        uint256 _cost,
        uint256 _bondMatchAmount,
        ERC20 _baseToken,
        IHyperdrive _hyperdrive
    ) internal returns (uint256) {
        // Transfer base tokens from long trader
        _baseToken.safeTransferFrom(
            _longOrder.trader,
            address(this),
            _baseTokenAmountLongOrder
        );

        // Transfer base tokens from short trader
        _baseToken.safeTransferFrom(
            _shortOrder.trader,
            address(this),
            _baseTokenAmountShortOrder
        );

        // Approve Hyperdrive
        // @dev Use balanceOf to get the total amount of base tokens instead of summing up the two amounts,
        //      in order to open the door for poential donation to help match orders.
        uint256 totalBaseTokenAmount = _baseToken.balanceOf(address(this));
        uint256 baseTokenAmountToUse = _cost + TOKEN_AMOUNT_BUFFER;
        if (totalBaseTokenAmount < baseTokenAmountToUse) {
            revert InsufficientFunding();
        }
        _baseToken.forceApprove(address(_hyperdrive), baseTokenAmountToUse);

        // Create PairOptions
        IHyperdrive.PairOptions memory pairOptions = IHyperdrive.PairOptions({
            longDestination: _longOrder.options.destination,
            shortDestination: _shortOrder.options.destination,
            asBase: true,
            extraData: ""
        });

        // Calculate minVaultSharePrice
        uint256 minVaultSharePrice = _longOrder.minVaultSharePrice.min(_shortOrder.minVaultSharePrice);

        // Mint matching positions
        ( , uint256 bondAmount) = _hyperdrive.mint(
            baseTokenAmountToUse,
            _bondMatchAmount,
            minVaultSharePrice,
            pairOptions
        );

        // Return the bondAmount   
        return bondAmount;
    }

    // TODO: Implement these functions
    function _handleBurn(){}
    function _handleLongTransfer(){}
    function _handleShortTransfer(){}

    /// @notice Get checkpoint and position durations from Hyperdrive contract
    /// @param _hyperdrive The Hyperdrive contract to query
    /// @return checkpointDuration The duration between checkpoints
    /// @return positionDuration The duration of positions
    /// @return flat The flat fee
    /// @return governanceLP The governance fee
    function _getHyperdriveDurationsAndFees(IHyperdrive _hyperdrive) internal view returns (
        uint256,uint256,uint256,uint256 
    ) {
        IHyperdrive.PoolConfig memory config = _hyperdrive.getPoolConfig();
        return (config.checkpointDuration, config.positionDuration, config.fees.flat, config.fees.governanceLP);
    }

    /// @dev Gets the most recent checkpoint time.
    /// @return latestCheckpoint The latest checkpoint.
    function _latestCheckpoint(uint256 _checkpointDuration)
        internal
        view
        returns (uint256 latestCheckpoint)
    {
        latestCheckpoint = HyperdriveMath.calculateCheckpointTime(
            block.timestamp,
            _checkpointDuration
        );
    }
}
