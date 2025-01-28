// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { ECDSA } from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import { ERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { IERC1271 } from "lib/openzeppelin-contracts/contracts/interfaces/IERC1271.sol";
import { ReentrancyGuard } from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { AssetId } from "../libraries/AssetId.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { HYPERDRIVE_MATCHING_ENGINE_KIND, VERSION } from "../libraries/Constants.sol";
import { HyperdriveMath } from "../libraries/HyperdriveMath.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IHyperdriveMatchingEngineV2 } from "../interfaces/IHyperdriveMatchingEngineV2.sol";

/// @author DELV
/// @title HyperdriveMatchingEngine
/// @notice A matching engine that processes order intents and settles trades on 
///         the Hyperdrive AMM.
/// @dev This version uses direct Hyperdrive mint/burn functions instead of flash 
///      loans.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract HyperdriveMatchingEngineV2 is 
    IHyperdriveMatchingEngineV2,
    ReentrancyGuard,
    EIP712
{
    using FixedPointMath for uint256;
    using SafeERC20 for ERC20;

    /// @notice The EIP712 typehash of the OrderIntent struct.
    bytes32 public constant ORDER_INTENT_TYPEHASH =
        keccak256(
            "OrderIntent(address trader,address counterparty,address feeRecipient,address hyperdrive,uint256 fundAmount,uint256 bondAmount,uint256 minVaultSharePrice,Options options,uint8 orderType,uint256 minMaturityTime,uint256 maxMaturityTime,uint256 expiry,bytes32 salt)"
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

    /// @notice The buffer amount used for cost related calculations.
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

    /// @notice Matches two orders
    /// @param _order1 The first order to match
    /// @param _order2 The second order to match
    /// @param _surplusRecipient The address that receives the surplus funds 
    ///         from matching the trades
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

        IHyperdrive hyperdrive = _order1.hyperdrive;

        // Handle different order type combinations
        if (_order1.orderType == OrderType.OpenLong && 
            _order2.orderType == OrderType.OpenShort) {
            // Case 1: Long + Short creation using mint()

            // Get necessary pool parameters
            IHyperdrive.PoolConfig memory config = _getHyperdriveDurationsAndFees(hyperdrive);
            
            uint256 latestCheckpoint = _latestCheckpoint(config.checkpointDuration);
            // @dev TODO: there is another way to get the info without calling
            //          getPoolInfo()?
            uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;

            // Calculate the amount of base tokens to transfer based on the 
            // bondMatchAmount
            uint256 openVaultSharePrice = hyperdrive.getCheckpoint(latestCheckpoint).vaultSharePrice;
            if (openVaultSharePrice == 0) {
                openVaultSharePrice = vaultSharePrice;
            }

            // Stack cycling to avoid stack-too-deep
            OrderIntent calldata order1 = _order1;
            OrderIntent calldata order2 = _order2;
            bytes32 order1Hash_ = order1Hash;
            bytes32 order2Hash_ = order2Hash;
            address surplusRecipient = _surplusRecipient;

            // Calculate matching amount
            // @dev This could have been placed before the control flow for
            //      shorter code, but it's put here to avoid stack-too-deep
            uint256 bondMatchAmount = _calculateBondMatchAmount(
                order1, 
                order2, 
                order1Hash_, 
                order2Hash_
            );

            
            // Get the sufficient funding amount to mint the bonds.
            // NOTE: Round the requred fund amount up to overestimate the cost.
            //       Round the flat fee calculation up and the governance fee
            //       calculation down to match the rounding used in the other flows.
            uint256 cost = bondMatchAmount.mulDivUp(
                vaultSharePrice.max(openVaultSharePrice), 
                openVaultSharePrice) + 
                bondMatchAmount.mulUp(config.fees.flat) +
                2 * bondMatchAmount.mulUp(config.fees.flat).mulDown(config.fees.governanceLP);

            // Calculate the amount of base tokens to transfer based on the 
            // bondMatchAmount
            // NOTE: Round the requred fund amount down to prevent overspending
            //       and possible reverting at a later step.
            uint256 baseTokenAmountOrder1 = order1.fundAmount.mulDivDown(bondMatchAmount, order1.bondAmount);
            uint256 baseTokenAmountOrder2 = order2.fundAmount.mulDivDown(bondMatchAmount, order2.bondAmount);

            // Update order fund amount used
            orderFundAmountUsed[order1Hash_] += baseTokenAmountOrder1;
            orderFundAmountUsed[order2Hash_] += baseTokenAmountOrder2;

            // Check if the fund amount used is greater than the order amount
            if (orderFundAmountUsed[order1Hash_] > order1.fundAmount || 
                orderFundAmountUsed[order2Hash_] > order2.fundAmount) {
                revert InvalidFundAmount();
            }

            // Calculate the maturity time of newly minted positions
            uint256 maturityTime = latestCheckpoint + config.positionDuration;

            // Check if the maturity time is within the range
            if (maturityTime < order1.minMaturityTime || maturityTime > order1.maxMaturityTime ||
                maturityTime < order2.minMaturityTime || maturityTime > order2.maxMaturityTime) {
                revert InvalidMaturityTime();
            }

            // @dev This could have been placed before the control flow for
            //      shorter code, but it's put here to avoid stack-too-deep
            IHyperdrive hyperdrive_ = order1.hyperdrive;
            ERC20 baseToken = ERC20(hyperdrive_.baseToken());

            // Mint the bonds
            uint256 bondAmount = _handleMint(
                order1, 
                order2, 
                baseTokenAmountOrder1, 
                baseTokenAmountOrder2,
                cost, 
                bondMatchAmount, 
                baseToken, 
                hyperdrive_);
            
            // Update order bond amount used
            orderBondAmountUsed[order1Hash_] += bondAmount;
            orderBondAmountUsed[order2Hash_] += bondAmount;

            // Mark fully executed orders as cancelled 
            if (orderBondAmountUsed[order1Hash_] >= order1.bondAmount || orderFundAmountUsed[order1Hash_] >= order1.fundAmount) {
                isCancelled[order1Hash_] = true;
            }
            if (orderBondAmountUsed[order2Hash_] >= order2.bondAmount || orderFundAmountUsed[order2Hash_] >= order2.fundAmount) {
                isCancelled[order2Hash_] = true;
            }

            // Transfer the remaining base tokens back to the surplus recipient
            baseToken.safeTransfer(
                surplusRecipient,
                baseToken.balanceOf(address(this))
            );
        } 


        else if (_order1.orderType == OrderType.CloseLong && 
                 _order2.orderType == OrderType.CloseShort) {
            // Case 2: Long + Short closing using burn()
            
            // Verify both orders have the same maturity time
            if (_order1.maxMaturityTime != _order2.maxMaturityTime) {
                revert InvalidMaturityTime();
            }
            
            // Calculate matching amount
            uint256 bondMatchAmount = _calculateBondMatchAmount(
                _order1, 
                _order2, 
                order1Hash, 
                order2Hash
            );

            // Update order bond amount used
            // @dev After the update, there is no need to check if the bond
            //      amount used is greater than the order amount, as the order
            //      amount is already used to calculate the bondMatchAmount.
            orderBondAmountUsed[order1Hash] += bondMatchAmount;
            orderBondAmountUsed[order2Hash] += bondMatchAmount;

            // Get the min fund output according to the bondMatchAmount
            // NOTE: Round the requred fund amount up to respect the order specified
            //       min fund output.
            uint256 minFundAmountOrder1 = (_order1.fundAmount - orderFundAmountUsed[order1Hash]).mulDivUp(bondMatchAmount, _order1.bondAmount);
            uint256 minFundAmountOrder2 = (_order2.fundAmount - orderFundAmountUsed[order2Hash]).mulDivUp(bondMatchAmount, _order2.bondAmount);

            // Get the base token
            ERC20 baseToken = ERC20(hyperdrive.baseToken());

            // Handle burn operation through helper function
            _handleBurn(
                _order1,
                _order2,
                minFundAmountOrder1,
                minFundAmountOrder2,
                bondMatchAmount,
                baseToken,
                hyperdrive
            );
            
            // Update order fund amount used
            orderFundAmountUsed[order1Hash] += minFundAmountOrder1;
            orderFundAmountUsed[order2Hash] += minFundAmountOrder2;

            // Mark fully executed orders as cancelled
            if (orderBondAmountUsed[order1Hash] >= _order1.bondAmount || 
                orderFundAmountUsed[order1Hash] >= _order1.fundAmount) {
                isCancelled[order1Hash] = true;
            }
            if (orderBondAmountUsed[order2Hash] >= _order2.bondAmount || 
                orderFundAmountUsed[order2Hash] >= _order2.fundAmount) {
                isCancelled[order2Hash] = true;
            }

            // Transfer the remaining base tokens back to the surplus recipient
            baseToken.safeTransfer(
                _surplusRecipient,
                baseToken.balanceOf(address(this))
            );
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
            _order2.trader,
            orderBondAmountUsed[order1Hash],
            orderBondAmountUsed[order2Hash],
            orderFundAmountUsed[order1Hash],
            orderFundAmountUsed[order2Hash]
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
        // Stack cycling to avoid stack-too-deep
        // OrderIntent calldata order = _order;

        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    ORDER_INTENT_TYPEHASH,
                    _order.trader,
                    _order.counterparty,
                    _order.feeRecipient,
                    address(_order.hyperdrive),
                    _order.fundAmount,
                    _order.bondAmount,
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

    /// @dev Validates orders before matching them.
    /// @param _order1 The first order to validate.
    /// @param _order2 The second order to validate.
    /// @return order1Hash The hash of the first order.
    /// @return order2Hash The hash of the second order.
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

        // For close orders, minMaturityTime must equal maxMaturityTime
        if (_order1.orderType == OrderType.CloseLong || 
            _order1.orderType == OrderType.CloseShort) {
            if (_order1.minMaturityTime != _order1.maxMaturityTime) {
                revert InvalidMaturityTime();
            }
        }
        if (_order2.orderType == OrderType.CloseLong || 
            _order2.orderType == OrderType.CloseShort) {
            if (_order2.minMaturityTime != _order2.maxMaturityTime) {
                revert InvalidMaturityTime();
            }
        }

        // Check that the destination is not the zero address
        if (_order1.options.destination == address(0) || 
            _order2.options.destination == address(0)) {
            revert InvalidDestination();
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

    }

    /// @dev Calculates the amount of bonds that can be matched between two orders.
    /// @param _order1 The first order to match.
    /// @param _order2 The second order to match.
    /// @param _order1Hash The hash of the first order.
    /// @param _order2Hash The hash of the second order.
    /// @return bondMatchAmount The amount of bonds that can be matched.
    function _calculateBondMatchAmount(
        OrderIntent calldata _order1,
        OrderIntent calldata _order2,
        bytes32 _order1Hash,
        bytes32 _order2Hash
    ) internal view returns (
        uint256 bondMatchAmount
    ) {
        uint256 order1BondAmountUsed = orderBondAmountUsed[_order1Hash];
        uint256 order2BondAmountUsed = orderBondAmountUsed[_order2Hash];

        if (order1BondAmountUsed >= _order1.bondAmount || order2BondAmountUsed >= _order2.bondAmount) {
            revert NoBondMatchAmount();
        }

        uint256 _order1BondAmount = _order1.bondAmount - order1BondAmountUsed;
        uint256 _order2BondAmount = _order2.bondAmount - order2BondAmountUsed;
            
        bondMatchAmount = _order1BondAmount.min(_order2BondAmount);
    }

    /// @dev Handles the minting of matching positions.
    /// @param _longOrder The order for opening a long position.
    /// @param _shortOrder The order for opening a short position.
    /// @param _baseTokenAmountLongOrder The amount of base tokens from the long 
    ///        order.
    /// @param _baseTokenAmountShortOrder The amount of base tokens from the short 
    ///        order.
    /// @param _cost The total cost of the operation.
    /// @param _bondMatchAmount The amount of bonds to mint.
    /// @param _baseToken The base token being used.
    /// @param _hyperdrive The Hyperdrive contract instance.
    /// @return The amount of bonds minted.
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
        // @dev Use balanceOf to get the total amount of base tokens instead of 
        //      summing up the two amounts, in order to open the door for poential 
        //      donation to help match orders.
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
        // @dev Take the larger of the two minVaultSharePrice as the min guard
        //      price to prevent slippage, so that it satisfies both orders.
        uint256 minVaultSharePrice = _longOrder.minVaultSharePrice.max(_shortOrder.minVaultSharePrice);

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

    /// @dev Handles the burning of matching positions.
    /// @param _longOrder The first order (CloseLong).
    /// @param _shortOrder The second order (CloseShort).
    /// @param _minFundAmountLongOrder The minimum fund amount for the long order.
    /// @param _minFundAmountShortOrder The minimum fund amount for the short order.
    /// @param _bondMatchAmount The amount of bonds to burn.
    /// @param _baseToken The base token being used.
    /// @param _hyperdrive The Hyperdrive contract instance.
    function _handleBurn(
        OrderIntent calldata _longOrder,
        OrderIntent calldata _shortOrder,
        uint256 _minFundAmountLongOrder,
        uint256 _minFundAmountShortOrder,
        uint256 _bondMatchAmount,
        ERC20 _baseToken,
        IHyperdrive _hyperdrive
    ) internal {
        
        // Get asset IDs for the long and short positions
        uint256 longAssetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            _longOrder.maxMaturityTime
        );
        uint256 shortAssetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Short,
            _shortOrder.maxMaturityTime
        );
        
        // This contract needs to take custody of the bonds before burning
        _hyperdrive.transferFrom(
            longAssetId,
            _longOrder.trader,
            address(this),
            _bondMatchAmount
        );
        _hyperdrive.transferFrom(
            shortAssetId,
            _shortOrder.trader,
            address(this),
            _bondMatchAmount
        );

        // Calculate minOutput and consider the potential donation to help match
        // orders.
        uint256 minOutput = (_minFundAmountLongOrder + _minFundAmountShortOrder) > _baseToken.balanceOf(address(this)) ? 
            _minFundAmountLongOrder + _minFundAmountShortOrder - _baseToken.balanceOf(address(this)) : 0;
        
        // Burn the matching positions
        _hyperdrive.burn(
            _longOrder.maxMaturityTime,
            _bondMatchAmount,
            minOutput,
            IHyperdrive.Options({
                destination: address(this),
                asBase: true,
                extraData: ""
            })
        );
        
        // Transfer proceeds to traders
        _baseToken.safeTransfer(_longOrder.options.destination, _minFundAmountLongOrder);
        _baseToken.safeTransfer(_shortOrder.options.destination, _minFundAmountShortOrder);
        
    }

    // TODO: Implement these functions
    function _handleLongTransfer() internal {}
    function _handleShortTransfer() internal {}

    /// @dev Get checkpoint and position durations from Hyperdrive contract
    /// @param _hyperdrive The Hyperdrive contract to query
    /// @return config The pool config
    function _getHyperdriveDurationsAndFees(IHyperdrive _hyperdrive) internal view returns (
        IHyperdrive.PoolConfig memory config
    ) {
        config = _hyperdrive.getPoolConfig();
    }

    /// @dev Gets the most recent checkpoint time.
    /// @param _checkpointDuration The duration of the checkpoint.
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
