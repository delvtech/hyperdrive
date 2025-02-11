// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { ECDSA } from "openzeppelin/utils/cryptography/ECDSA.sol";
import { EIP712 } from "openzeppelin/utils/cryptography/EIP712.sol";
import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { IERC1271 } from "openzeppelin/interfaces/IERC1271.sol";
import { ReentrancyGuard } from "openzeppelin/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
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
            "OrderIntent(address trader,address counterparty,address hyperdrive,uint256 fundAmount,uint256 bondAmount,uint256 minVaultSharePrice,Options options,uint8 orderType,uint256 minMaturityTime,uint256 maxMaturityTime,uint256 expiry,bytes32 salt)"
        );

    /// @notice The EIP712 typehash of the Options struct.
    bytes32 public constant OPTIONS_TYPEHASH =
        keccak256("Options(address destination,bool asBase)");

    /// @notice The name of this matching engine.
    string public name;

    /// @notice The kind of this matching engine.
    string public constant kind = HYPERDRIVE_MATCHING_ENGINE_KIND;

    /// @notice The version of this matching engine.
    string public constant version = VERSION;

    /// @notice The buffer amount used for cost related calculations.
    /// @dev TODO: The buffer amount needs more testing.
    uint256 public constant TOKEN_AMOUNT_BUFFER = 10;

    /// @notice Mapping to track cancelled orders.
    mapping(bytes32 => bool) public isCancelled;

    /// @notice Mapping to track the amounts used for each order.
    mapping(bytes32 => OrderAmounts) public orderAmountsUsed;

    /// @notice Initializes the matching engine.
    /// @param _name The name of this matching engine.
    constructor(string memory _name) EIP712(_name, VERSION) {
        name = _name;
    }

    /// @notice Matches two orders. The ordering of the inputs matters, and
    ///         the general rule is to put the open order before the close
    ///         order and the long order before the short order. For example,
    ///         OpenLong + CloseLong is valid, but CloseLong + OpenLong is
    ///         invalid; OpenLong + OpenShort is valid, but OpenShort +
    ///         OpenLong is invalid.
    /// @param _order1 The first order to match.
    /// @param _order2 The second order to match.
    /// @param _surplusRecipient The address that receives the surplus funds
    ///         from matching the trades.
    function matchOrders(
        OrderIntent calldata _order1,
        OrderIntent calldata _order2,
        address _surplusRecipient
    ) external nonReentrant {
        // Set the surplus recipient to the caller if not specified.
        if (_surplusRecipient == address(0)) {
            _surplusRecipient = msg.sender;
        }

        // Validate orders.
        (bytes32 order1Hash, bytes32 order2Hash) = _validateOrdersNoTaker(
            _order1,
            _order2
        );

        IHyperdrive hyperdrive = _order1.hyperdrive;
        ERC20 fundToken;
        if (_order1.options.asBase) {
            fundToken = ERC20(hyperdrive.baseToken());
        } else {
            fundToken = ERC20(hyperdrive.vaultSharesToken());
        }

        // Handle different order type combinations.
        // Case 1: Long + Short creation using mint().
        if (
            _order1.orderType == OrderType.OpenLong &&
            _order2.orderType == OrderType.OpenShort
        ) {
            // Calculate matching amount.
            // @dev This could have been placed before the control flow for
            //      shorter code, but it's put here to avoid stack-too-deep.
            uint256 bondMatchAmount = _calculateBondMatchAmount(
                _order1,
                _order2,
                order1Hash,
                order2Hash
            );

            // Calculate the amount of fund tokens to transfer based on the
            // bondMatchAmount using dynamic pricing. During a series of partial
            // matching, the pricing requirements can go easier as needed for each
            // new match, hence increasing the match likelihood.
            // NOTE: Round the required fund amount down to prevent overspending
            //       and possible reverting at a later step.
            uint256 fundTokenAmountOrder1 = (_order1.fundAmount -
                orderAmountsUsed[order1Hash].fundAmount).mulDivDown(
                    bondMatchAmount,
                    (_order1.bondAmount -
                        orderAmountsUsed[order1Hash].bondAmount)
                );
            uint256 fundTokenAmountOrder2 = (_order2.fundAmount -
                orderAmountsUsed[order2Hash].fundAmount).mulDivDown(
                    bondMatchAmount,
                    (_order2.bondAmount -
                        orderAmountsUsed[order2Hash].bondAmount)
                );

            // Update order fund amount used.
            _updateOrderAmount(order1Hash, fundTokenAmountOrder1, false);
            _updateOrderAmount(order2Hash, fundTokenAmountOrder2, false);

            // Check if the fund amount used is greater than the order amount.
            if (
                orderAmountsUsed[order1Hash].fundAmount > _order1.fundAmount ||
                orderAmountsUsed[order2Hash].fundAmount > _order2.fundAmount
            ) {
                revert InvalidFundAmount();
            }

            // Calculate costs and parameters.
            (uint256 maturityTime, uint256 cost) = _calculateMintCost(
                hyperdrive,
                bondMatchAmount
            );

            // Check if the maturity time is within the range.
            if (
                maturityTime < _order1.minMaturityTime ||
                maturityTime > _order1.maxMaturityTime ||
                maturityTime < _order2.minMaturityTime ||
                maturityTime > _order2.maxMaturityTime
            ) {
                revert InvalidMaturityTime();
            }

            // Mint the bonds.
            uint256 bondAmount = _handleMint(
                _order1,
                _order2,
                fundTokenAmountOrder1,
                fundTokenAmountOrder2,
                cost,
                bondMatchAmount,
                fundToken,
                hyperdrive
            );

            // Update order bond amount used.
            _updateOrderAmount(order1Hash, bondAmount, true);
            _updateOrderAmount(order2Hash, bondAmount, true);
        }
        // Case 2: Long + Short closing using burn().
        else if (
            _order1.orderType == OrderType.CloseLong &&
            _order2.orderType == OrderType.CloseShort
        ) {
            // Verify both orders have the same maturity time.
            if (_order1.maxMaturityTime != _order2.maxMaturityTime) {
                revert InvalidMaturityTime();
            }

            // Calculate matching amount.
            uint256 bondMatchAmount = _calculateBondMatchAmount(
                _order1,
                _order2,
                order1Hash,
                order2Hash
            );

            // Get the min fund output according to the bondMatchAmount.
            // NOTE: Round the required fund amount up to respect the order specified
            //       min fund output.
            uint256 minFundAmountOrder1 = (_order1.fundAmount -
                orderAmountsUsed[order1Hash].fundAmount).mulDivUp(
                    bondMatchAmount,
                    (_order1.bondAmount -
                        orderAmountsUsed[order1Hash].bondAmount)
                );
            uint256 minFundAmountOrder2 = (_order2.fundAmount -
                orderAmountsUsed[order2Hash].fundAmount).mulDivUp(
                    bondMatchAmount,
                    (_order2.bondAmount -
                        orderAmountsUsed[order2Hash].bondAmount)
                );

            // Update order bond amount used.
            // @dev After the update, there is no need to check if the bond
            //      amount used is greater than the order amount, as the order
            //      amount is already used to calculate the bondMatchAmount.
            _updateOrderAmount(order1Hash, bondMatchAmount, true);
            _updateOrderAmount(order2Hash, bondMatchAmount, true);

            // Handle burn operation through helper function.
            _handleBurn(
                _order1,
                _order2,
                minFundAmountOrder1,
                minFundAmountOrder2,
                bondMatchAmount,
                fundToken,
                hyperdrive
            );

            // Update order fund amount used.
            _updateOrderAmount(order1Hash, minFundAmountOrder1, false);
            _updateOrderAmount(order2Hash, minFundAmountOrder2, false);
        }
        // Case 3: Transfer positions between traders.
        else if (
            (_order1.orderType == OrderType.OpenLong &&
                _order2.orderType == OrderType.CloseLong) ||
            (_order1.orderType == OrderType.OpenShort &&
                _order2.orderType == OrderType.CloseShort)
        ) {
            // Verify that the maturity time of the close order matches the
            // open order's requirements.
            if (
                _order2.maxMaturityTime > _order1.maxMaturityTime ||
                _order2.maxMaturityTime < _order1.minMaturityTime
            ) {
                revert InvalidMaturityTime();
            }

            // Calculate matching amount.
            uint256 bondMatchAmount = _calculateBondMatchAmount(
                _order1,
                _order2,
                order1Hash,
                order2Hash
            );

            // Calculate the amount of fund tokens to transfer based on the
            // bondMatchAmount using dynamic pricing. During a series of partial
            // matching, the pricing requirements can go easier as needed for each
            // new match, hence increasing the match likelihood.
            // NOTE: Round the required fund amount down to prevent overspending
            //       and possible reverting at a later step.
            uint256 fundTokenAmountOrder1 = (_order1.fundAmount -
                orderAmountsUsed[order1Hash].fundAmount).mulDivDown(
                    bondMatchAmount,
                    (_order1.bondAmount -
                        orderAmountsUsed[order1Hash].bondAmount)
                );

            // Get the min fund output according to the bondMatchAmount.
            // NOTE: Round the required fund amount up to respect the order specified
            //       min fund output.
            uint256 minFundAmountOrder2 = (_order2.fundAmount -
                orderAmountsUsed[order2Hash].fundAmount).mulDivUp(
                    bondMatchAmount,
                    (_order2.bondAmount -
                        orderAmountsUsed[order2Hash].bondAmount)
                );

            // Check if trader 1 has enough fund to transfer to trader 2.
            // @dev Also considering any donations to help match the orders.
            if (
                fundTokenAmountOrder1 + fundToken.balanceOf(address(this)) <
                minFundAmountOrder2
            ) {
                revert InsufficientFunding();
            }

            // Update order bond amount used.
            // @dev After the update, there is no need to check if the bond
            //      amount used is greater than the order amount, as the order
            //      amount is already used to calculate the bondMatchAmount.
            _updateOrderAmount(order1Hash, bondMatchAmount, true);
            _updateOrderAmount(order2Hash, bondMatchAmount, true);

            _handleTransfer(
                _order1,
                _order2,
                fundTokenAmountOrder1,
                minFundAmountOrder2,
                bondMatchAmount,
                fundToken,
                hyperdrive
            );

            // Update order fund amount used.
            _updateOrderAmount(order1Hash, fundTokenAmountOrder1, false);
            _updateOrderAmount(order2Hash, minFundAmountOrder2, false);
        }
        // All other cases are invalid.
        else {
            revert InvalidOrderCombination();
        }

        // Transfer the remaining fund tokens back to the surplus recipient.
        uint256 remainingBalance = fundToken.balanceOf(address(this));
        if (remainingBalance > 0) {
            fundToken.safeTransfer(_surplusRecipient, remainingBalance);
        }

        emit OrdersMatched(
            hyperdrive,
            order1Hash,
            order2Hash,
            _order1.trader,
            _order2.trader,
            orderAmountsUsed[order1Hash].bondAmount,
            orderAmountsUsed[order2Hash].bondAmount,
            orderAmountsUsed[order1Hash].fundAmount,
            orderAmountsUsed[order2Hash].fundAmount
        );
    }

    /// @notice Fills a maker order by the taker.
    /// @param _makerOrder The maker order to fill.
    /// @param _takerOrder The taker order created on the fly by the frontend.
    /// @dev The frontend will have to take some necessary values from the user
    ///      like the destination address, the orderType, and the maturity time
    ///      for the close position...etc., and create the minimal sufficient
    ///      struct as the _takerOrder argument. For example:
    ///
    /// OrderIntent({
    ///    trader: msg.sender, // Take the user's address.
    ///    counterparty: address(0), // Not needed for immediate fill.
    ///    hyperdrive: IHyperdrive(address(0)), // Not needed for immediate fill.
    ///    fundAmount: 0,  // Not needed for immediate fill.
    ///    bondAmount: _bondAmount,  // Take from the user's input.
    ///    minVaultSharePrice: _makerOrder.minVaultSharePrice, // From maker order.
    ///    options: IHyperdrive.Options({
    ///        // Take destination from the user's input; if null, set to msg.sender.
    ///        destination: _destination or msg.sender,
    ///        asBase: _makerOrder.options.asBase, // From maker order.
    ///        extraData: ""
    ///    }),
    ///    orderType: _takerOrderType, // Take from the user's input.
    ///    // For closing positions, take maturity time from the user's input;
    ///    // otherwise, use values from the maker order.
    ///    minMaturityTime: _closeOrderMaturityTime or _makerOrder.minMaturityTime,
    ///    maxMaturityTime: _closeOrderMaturityTime or _makerOrder.maxMaturityTime,
    ///    expiry: 0,  // Not needed for immediate fill.
    ///    salt: 0,                      // Not needed for immediate fill.
    ///    signature: ""                 // Not needed for immediate fill.
    /// })
    function fillOrder(
        OrderIntent calldata _makerOrder,
        OrderIntent calldata _takerOrder
    ) external nonReentrant {
        // Validate maker order and taker order.
        bytes32 makerOrderHash = _validateOrdersWithTaker(
            _makerOrder,
            _takerOrder
        );

        // Calculates the amount of bonds that can be matched between two orders.
        OrderAmounts memory amountsMaker = orderAmountsUsed[makerOrderHash];
        uint256 makerBondAmount = _makerOrder.bondAmount -
            amountsMaker.bondAmount;
        uint256 bondMatchAmount = makerBondAmount.min(_takerOrder.bondAmount);

        IHyperdrive hyperdrive = _makerOrder.hyperdrive;
        ERC20 fundToken;
        if (_makerOrder.options.asBase) {
            fundToken = ERC20(hyperdrive.baseToken());
        } else {
            fundToken = ERC20(hyperdrive.vaultSharesToken());
        }

        // Handle different maker order types.
        if (_makerOrder.orderType == OrderType.OpenLong) {
            if (_takerOrder.orderType == OrderType.OpenShort) {
                // OpenLong + OpenShort: _handleMint().
                // Calculate the amount of fund tokens to transfer based on the
                // bondMatchAmount using dynamic pricing. During a series of partial
                // matching, the pricing requirements can go easier as needed for
                // each new match, hence increasing the match likelihood.
                // NOTE: Round the required fund amount down to prevent overspending
                //       and possible reverting at a later step.
                uint256 fundTokenAmountMaker = (_makerOrder.fundAmount -
                    orderAmountsUsed[makerOrderHash].fundAmount).mulDivDown(
                        bondMatchAmount,
                        (_makerOrder.bondAmount -
                            orderAmountsUsed[makerOrderHash].bondAmount)
                    );

                // Update order fund amount used.
                _updateOrderAmount(makerOrderHash, fundTokenAmountMaker, false);

                // Check if the fund amount used is greater than the order amount.
                if (
                    orderAmountsUsed[makerOrderHash].fundAmount >
                    _makerOrder.fundAmount
                ) {
                    revert InvalidFundAmount();
                }

                // Calculate costs and parameters.
                (uint256 maturityTime, uint256 cost) = _calculateMintCost(
                    hyperdrive,
                    bondMatchAmount
                );

                // Check if the maturity time is within the range.
                if (
                    maturityTime < _makerOrder.minMaturityTime ||
                    maturityTime > _makerOrder.maxMaturityTime
                ) {
                    revert InvalidMaturityTime();
                }

                // Calculate the amount of fund tokens the taker needs to pay.
                uint256 fundTokenAmountTaker = fundTokenAmountMaker >
                    cost + TOKEN_AMOUNT_BUFFER
                    ? 0
                    : cost + TOKEN_AMOUNT_BUFFER - fundTokenAmountMaker;

                // Mint the bonds.
                uint256 bondAmount = _handleMint(
                    _makerOrder,
                    _takerOrder,
                    fundTokenAmountMaker,
                    fundTokenAmountTaker,
                    cost,
                    bondMatchAmount,
                    fundToken,
                    hyperdrive
                );

                // Update order bond amount used.
                _updateOrderAmount(makerOrderHash, bondAmount, true);
            } else if (_takerOrder.orderType == OrderType.CloseLong) {
                // OpenLong + CloseLong: _handleTransfer().
                // Verify that the maturity time of the close order matches the
                // open order's requirements.
                if (
                    _takerOrder.maxMaturityTime > _makerOrder.maxMaturityTime ||
                    _takerOrder.maxMaturityTime < _makerOrder.minMaturityTime
                ) {
                    revert InvalidMaturityTime();
                }

                // Calculate the amount of fund tokens to transfer based on the
                // bondMatchAmount using dynamic pricing. During a series of partial
                // matching, the pricing requirements can go easier as needed for each
                // new match, hence increasing the match likelihood.
                // NOTE: Round the required fund amount down to prevent overspending
                //       and possible reverting at a later step.
                uint256 fundTokenAmountMaker = (_makerOrder.fundAmount -
                    orderAmountsUsed[makerOrderHash].fundAmount).mulDivDown(
                        bondMatchAmount,
                        (_makerOrder.bondAmount -
                            orderAmountsUsed[makerOrderHash].bondAmount)
                    );

                // The taker simply agrees with the maker's fund amount, and no
                // additional donation nor validations need to be considered
                uint256 minFundAmountTaker = fundTokenAmountMaker;

                // Update order bond amount used.
                // @dev After the update, there is no need to check if the bond
                //      amount used is greater than the order amount, as the order
                //      amount is already used to calculate the bondMatchAmount.
                _updateOrderAmount(makerOrderHash, bondMatchAmount, true);

                _handleTransfer(
                    _makerOrder,
                    _takerOrder,
                    fundTokenAmountMaker,
                    minFundAmountTaker,
                    bondMatchAmount,
                    fundToken,
                    hyperdrive
                );

                // Update order fund amount used.
                _updateOrderAmount(makerOrderHash, fundTokenAmountMaker, false);
            } else {
                revert InvalidOrderCombination();
            }
        } else if (_makerOrder.orderType == OrderType.OpenShort) {
            if (_takerOrder.orderType == OrderType.OpenLong) {
                // OpenShort + OpenLong: _handleMint() but reverse the order.
                // Calculate the amount of fund tokens to transfer based on the
                // bondMatchAmount using dynamic pricing. During a series of partial
                // matching, the pricing requirements can go easier as needed for
                // each new match, hence increasing the match likelihood.
                // NOTE: Round the required fund amount down to prevent overspending
                //       and possible reverting at a later step.
                uint256 fundTokenAmountMaker = (_makerOrder.fundAmount -
                    orderAmountsUsed[makerOrderHash].fundAmount).mulDivDown(
                        bondMatchAmount,
                        (_makerOrder.bondAmount -
                            orderAmountsUsed[makerOrderHash].bondAmount)
                    );

                // Update order fund amount used.
                _updateOrderAmount(makerOrderHash, fundTokenAmountMaker, false);

                // Check if the fund amount used is greater than the order amount.
                if (
                    orderAmountsUsed[makerOrderHash].fundAmount >
                    _makerOrder.fundAmount
                ) {
                    revert InvalidFundAmount();
                }

                // Calculate costs and parameters.
                (uint256 maturityTime, uint256 cost) = _calculateMintCost(
                    hyperdrive,
                    bondMatchAmount
                );

                // Check if the maturity time is within the range.
                if (
                    maturityTime < _makerOrder.minMaturityTime ||
                    maturityTime > _makerOrder.maxMaturityTime
                ) {
                    revert InvalidMaturityTime();
                }

                // Calculate the amount of fund tokens the taker needs to pay.
                uint256 fundTokenAmountTaker = fundTokenAmountMaker >
                    cost + TOKEN_AMOUNT_BUFFER
                    ? 0
                    : cost + TOKEN_AMOUNT_BUFFER - fundTokenAmountMaker;

                // Mint the bonds.
                uint256 bondAmount = _handleMint(
                    _takerOrder,
                    _makerOrder,
                    fundTokenAmountTaker,
                    fundTokenAmountMaker,
                    cost,
                    bondMatchAmount,
                    fundToken,
                    hyperdrive
                );

                // Update order bond amount used.
                _updateOrderAmount(makerOrderHash, bondAmount, true);
            } else if (_takerOrder.orderType == OrderType.CloseShort) {
                // OpenShort + CloseShort: _handleTransfer().
                // Verify that the maturity time of the close order matches the
                // open order's requirements.
                if (
                    _takerOrder.maxMaturityTime > _makerOrder.maxMaturityTime ||
                    _takerOrder.maxMaturityTime < _makerOrder.minMaturityTime
                ) {
                    revert InvalidMaturityTime();
                }

                // Calculate the amount of fund tokens to transfer based on the
                // bondMatchAmount using dynamic pricing. During a series of partial
                // matching, the pricing requirements can go easier as needed for each
                // new match, hence increasing the match likelihood.
                // NOTE: Round the required fund amount down to prevent overspending
                //       and possible reverting at a later step.
                uint256 fundTokenAmountMaker = (_makerOrder.fundAmount -
                    orderAmountsUsed[makerOrderHash].fundAmount).mulDivDown(
                        bondMatchAmount,
                        (_makerOrder.bondAmount -
                            orderAmountsUsed[makerOrderHash].bondAmount)
                    );

                // The taker simply agrees with the maker's fund amount, and no
                // additional donation nor validations need to be considered
                uint256 minFundAmountTaker = fundTokenAmountMaker;

                // Update order bond amount used.
                // @dev After the update, there is no need to check if the bond
                //      amount used is greater than the order amount, as the order
                //      amount is already used to calculate the bondMatchAmount.
                _updateOrderAmount(makerOrderHash, bondMatchAmount, true);

                _handleTransfer(
                    _makerOrder,
                    _takerOrder,
                    fundTokenAmountMaker,
                    minFundAmountTaker,
                    bondMatchAmount,
                    fundToken,
                    hyperdrive
                );

                // Update order fund amount used.
                _updateOrderAmount(makerOrderHash, fundTokenAmountMaker, false);
            } else {
                revert InvalidOrderCombination();
            }
        } else if (_makerOrder.orderType == OrderType.CloseLong) {
            if (_takerOrder.orderType == OrderType.OpenLong) {
                // CloseLong + OpenLong: _handleTransfer() but reverse the order.
                // Verify that the maturity time of the close order matches the
                // open order's requirements.
                if (
                    _makerOrder.maxMaturityTime > _takerOrder.maxMaturityTime ||
                    _makerOrder.maxMaturityTime < _takerOrder.minMaturityTime
                ) {
                    revert InvalidMaturityTime();
                }

                // Calculate the amount of fund tokens to transfer based on the
                // bondMatchAmount using dynamic pricing. During a series of partial
                // matching, the pricing requirements can go easier as needed for each
                // new match, hence increasing the match likelihood.
                // NOTE: Round the required fund amount down to prevent overspending
                //       and possible reverting at a later step.
                uint256 minFundAmountMaker = (_makerOrder.fundAmount -
                    orderAmountsUsed[makerOrderHash].fundAmount).mulDivDown(
                        bondMatchAmount,
                        (_makerOrder.bondAmount -
                            orderAmountsUsed[makerOrderHash].bondAmount)
                    );

                // The taker simply agrees with the maker's fund amount, and no
                // additional donation nor validations need to be considered
                uint256 fundTokenAmountTaker = minFundAmountMaker;

                // Update order bond amount used.
                // @dev After the update, there is no need to check if the bond
                //      amount used is greater than the order amount, as the order
                //      amount is already used to calculate the bondMatchAmount.
                _updateOrderAmount(makerOrderHash, bondMatchAmount, true);

                _handleTransfer(
                    _takerOrder,
                    _makerOrder,
                    fundTokenAmountTaker,
                    minFundAmountMaker,
                    bondMatchAmount,
                    fundToken,
                    hyperdrive
                );

                // Update order fund amount used.
                _updateOrderAmount(makerOrderHash, minFundAmountMaker, false);
            } else if (_takerOrder.orderType == OrderType.CloseShort) {
                // CloseLong + CloseShort: _handleBurn().
                // Verify both orders have the same maturity time.
                if (
                    _makerOrder.maxMaturityTime != _takerOrder.maxMaturityTime
                ) {
                    revert InvalidMaturityTime();
                }

                // Get the min fund output according to the bondMatchAmount.
                // NOTE: Round the required fund amount up to respect the order
                //       specified min fund output.
                uint256 minFundAmountMaker = (_makerOrder.fundAmount -
                    orderAmountsUsed[makerOrderHash].fundAmount).mulDivUp(
                        bondMatchAmount,
                        (_makerOrder.bondAmount -
                            orderAmountsUsed[makerOrderHash].bondAmount)
                    );

                // The taker takes whatever the leftover fund amount is.
                // @dev The taker will not receive proceeds inside the _handleBurn(),
                //      but will receive the leftover fund at the surplus distribution.
                uint256 minFundAmountTaker = 0;

                // Update order bond amount used.
                // @dev After the update, there is no need to check if the bond
                //      amount used is greater than the order amount, as the order
                //      amount is already used to calculate the bondMatchAmount.
                _updateOrderAmount(makerOrderHash, bondMatchAmount, true);

                // Handle burn operation through helper function.
                _handleBurn(
                    _makerOrder,
                    _takerOrder,
                    minFundAmountMaker,
                    minFundAmountTaker,
                    bondMatchAmount,
                    fundToken,
                    hyperdrive
                );

                // Update order fund amount used.
                _updateOrderAmount(makerOrderHash, minFundAmountMaker, false);
            } else {
                revert InvalidOrderCombination();
            }
        } else if (_makerOrder.orderType == OrderType.CloseShort) {
            if (_takerOrder.orderType == OrderType.OpenShort) {
                // CloseShort + OpenShort: _handleTransfer() but reverse the order.
                // Verify that the maturity time of the close order matches the
                // open order's requirements.
                if (
                    _makerOrder.maxMaturityTime > _takerOrder.maxMaturityTime ||
                    _makerOrder.maxMaturityTime < _takerOrder.minMaturityTime
                ) {
                    revert InvalidMaturityTime();
                }

                // Calculate the amount of fund tokens to transfer based on the
                // bondMatchAmount using dynamic pricing. During a series of partial
                // matching, the pricing requirements can go easier as needed for each
                // new match, hence increasing the match likelihood.
                // NOTE: Round the required fund amount down to prevent overspending
                //       and possible reverting at a later step.
                uint256 minFundAmountMaker = (_makerOrder.fundAmount -
                    orderAmountsUsed[makerOrderHash].fundAmount).mulDivDown(
                        bondMatchAmount,
                        (_makerOrder.bondAmount -
                            orderAmountsUsed[makerOrderHash].bondAmount)
                    );

                // The taker simply agrees with the maker's fund amount, and no
                // additional donation nor validations need to be considered
                uint256 fundTokenAmountTaker = minFundAmountMaker;

                // Update order bond amount used.
                // @dev After the update, there is no need to check if the bond
                //      amount used is greater than the order amount, as the order
                //      amount is already used to calculate the bondMatchAmount.
                _updateOrderAmount(makerOrderHash, bondMatchAmount, true);

                _handleTransfer(
                    _takerOrder,
                    _makerOrder,
                    fundTokenAmountTaker,
                    minFundAmountMaker,
                    bondMatchAmount,
                    fundToken,
                    hyperdrive
                );

                // Update order fund amount used.
                _updateOrderAmount(makerOrderHash, minFundAmountMaker, false);
            } else if (_takerOrder.orderType == OrderType.CloseLong) {
                // CloseShort + CloseLong: _handleBurn() but reverse the order.
                // Verify both orders have the same maturity time.
                if (
                    _makerOrder.maxMaturityTime != _takerOrder.maxMaturityTime
                ) {
                    revert InvalidMaturityTime();
                }

                // Get the min fund output according to the bondMatchAmount.
                // NOTE: Round the required fund amount up to respect the order
                //       specified min fund output.
                uint256 minFundAmountMaker = (_makerOrder.fundAmount -
                    orderAmountsUsed[makerOrderHash].fundAmount).mulDivUp(
                        bondMatchAmount,
                        (_makerOrder.bondAmount -
                            orderAmountsUsed[makerOrderHash].bondAmount)
                    );

                // The taker takes whatever the leftover fund amount is.
                // @dev The taker will not receive proceeds inside the _handleBurn(),
                //      but will receive the leftover fund at the surplus distribution.
                uint256 minFundAmountTaker = 0;

                // Update order bond amount used.
                // @dev After the update, there is no need to check if the bond
                //      amount used is greater than the order amount, as the order
                //      amount is already used to calculate the bondMatchAmount.
                _updateOrderAmount(makerOrderHash, bondMatchAmount, true);

                // Handle burn operation through helper function.
                _handleBurn(
                    _takerOrder,
                    _makerOrder,
                    minFundAmountTaker,
                    minFundAmountMaker,
                    bondMatchAmount,
                    fundToken,
                    hyperdrive
                );

                // Update order fund amount used.
                _updateOrderAmount(makerOrderHash, minFundAmountMaker, false);
            } else {
                revert InvalidOrderCombination();
            }
        } else {
            revert InvalidOrderCombination();
        }

        // Transfer any remaining fund tokens back to the taker's destination.
        uint256 remainingBalance = fundToken.balanceOf(address(this));
        if (remainingBalance > 0) {
            fundToken.safeTransfer(
                _takerOrder.options.destination,
                remainingBalance
            );
        }

        emit OrderFilled(
            _makerOrder.hyperdrive,
            makerOrderHash,
            _makerOrder.trader,
            _takerOrder.trader,
            orderAmountsUsed[makerOrderHash].bondAmount,
            orderAmountsUsed[makerOrderHash].fundAmount
        );
    }

    /// @notice Allows traders to cancel their orders.
    /// @param _orders Array of orders to cancel.
    function cancelOrders(
        OrderIntent[] calldata _orders
    ) external nonReentrant {
        bytes32[] memory orderHashes = new bytes32[](_orders.length);
        for (uint256 i = 0; i < _orders.length; i++) {
            // Ensure sender is the trader.
            if (msg.sender != _orders[i].trader) {
                revert InvalidSender();
            }

            // Verify signature.
            bytes32 orderHash = hashOrderIntent(_orders[i]);
            if (!verifySignature(orderHash, _orders[i].signature, msg.sender)) {
                revert InvalidSignature();
            }

            // Cancel the order.
            isCancelled[orderHash] = true;
            orderHashes[i] = orderHash;
        }

        emit OrdersCancelled(msg.sender, orderHashes);
    }

    /// @notice Hashes an order intent according to EIP-712.
    /// @param _order The order intent to hash.
    /// @return The hash of the order intent.
    /// @dev Use two helper functions to encode to avoid stack too deep.
    // function hashOrderIntent(
    //     OrderIntent calldata _order
    // ) public view returns (bytes32) {
    //     return
    //         _hashTypedDataV4(
    //             keccak256(
    //                 abi.encode(
    //                     ORDER_INTENT_TYPEHASH,
    //                     _order.trader,
    //                     _order.counterparty,
    //                     address(_order.hyperdrive),
    //                     _order.fundAmount,
    //                     _order.bondAmount,
    //                     _order.minVaultSharePrice,
    //                     keccak256(
    //                         abi.encode(
    //                             OPTIONS_TYPEHASH,
    //                             _order.options.destination,
    //                             _order.options.asBase
    //                         )
    //                     ),
    //                     uint8(_order.orderType),
    //                     _order.minMaturityTime,
    //                     _order.maxMaturityTime,
    //                     _order.expiry,
    //                     _order.salt
    //                 )
    //             )
    //         );
    // }
    function hashOrderIntent(
        OrderIntent calldata _order
    ) public view returns (bytes32) {
        // Get the encoded parts.
        bytes memory encodedPart1 = _encodeOrderPart1(_order);
        bytes memory encodedPart2 = _encodeOrderPart2(_order);
        
        // Concatenate and calculate the final hash
        return _hashTypedDataV4(
            keccak256(
                bytes.concat(
                    encodedPart1,
                    encodedPart2
                )
            )
        );
    }

    /// @notice Verifies a signature for a given signer.
    /// @param _hash The EIP-712 hash of the order.
    /// @param _signature The signature bytes.
    /// @param _signer The expected signer.
    /// @return True if signature is valid, false otherwise.
    function verifySignature(
        bytes32 _hash,
        bytes calldata _signature,
        address _signer
    ) public view returns (bool) {
        // For contracts, use EIP-1271.
        if (_signer.code.length > 0) {
            try IERC1271(_signer).isValidSignature(_hash, _signature) returns (
                bytes4 magicValue
            ) {
                return magicValue == IERC1271.isValidSignature.selector;
            } catch {
                return false;
            }
        }

        // For EOAs, verify ECDSA signature.
        return ECDSA.recover(_hash, _signature) == _signer;
    }

    /// @dev Encodes the first part of the order intent.
    /// @param _order The order intent to encode.
    /// @return The encoded part of the order intent.
    function _encodeOrderPart1(
        OrderIntent calldata _order
    ) internal pure returns (bytes memory) {
        return abi.encode(
            ORDER_INTENT_TYPEHASH,
            _order.trader,
            _order.counterparty,
            address(_order.hyperdrive),
            _order.fundAmount,
            _order.bondAmount
        );
    }

    /// @dev Encodes the second part of the order intent.
    /// @param _order The order intent to encode.
    /// @return The encoded part of the order intent.
    function _encodeOrderPart2(
        OrderIntent calldata _order
    ) internal pure returns (bytes memory) {
        bytes32 optionsHash = keccak256(
            abi.encode(
                OPTIONS_TYPEHASH,
                _order.options.destination,
                _order.options.asBase
            )
        );
        
        return abi.encode(
            _order.minVaultSharePrice,
            optionsHash,
            uint8(_order.orderType),
            _order.minMaturityTime,
            _order.maxMaturityTime,
            _order.expiry,
            _order.salt
        );
    }

    /// @dev Validates orders before matching them.
    /// @param _order1 The first order to validate.
    /// @param _order2 The second order to validate.
    /// @return order1Hash The hash of the first order.
    /// @return order2Hash The hash of the second order.
    function _validateOrdersNoTaker(
        OrderIntent calldata _order1,
        OrderIntent calldata _order2
    ) internal view returns (bytes32 order1Hash, bytes32 order2Hash) {
        // Verify counterparties.
        if (
            (_order1.counterparty != address(0) &&
                _order1.counterparty != _order2.trader) ||
            (_order2.counterparty != address(0) &&
                _order2.counterparty != _order1.trader)
        ) {
            revert InvalidCounterparty();
        }

        // Check expiry.
        if (
            _order1.expiry <= block.timestamp ||
            _order2.expiry <= block.timestamp
        ) {
            revert AlreadyExpired();
        }

        // Verify Hyperdrive instance.
        if (_order1.hyperdrive != _order2.hyperdrive) {
            revert MismatchedHyperdrive();
        }

        // Verify settlement asset.
        // @dev TODO: only supporting both true or both false for now.
        //      Supporting mixed asBase values needs code changes on the Hyperdrive
        //      instances.
        if (_order1.options.asBase != _order2.options.asBase) {
            revert InvalidSettlementAsset();
        }

        // Verify valid maturity time.
        if (
            _order1.minMaturityTime > _order1.maxMaturityTime ||
            _order2.minMaturityTime > _order2.maxMaturityTime
        ) {
            revert InvalidMaturityTime();
        }

        // For close orders, minMaturityTime must equal maxMaturityTime.
        if (
            _order1.orderType == OrderType.CloseLong ||
            _order1.orderType == OrderType.CloseShort
        ) {
            if (_order1.minMaturityTime != _order1.maxMaturityTime) {
                revert InvalidMaturityTime();
            }
        }
        if (
            _order2.orderType == OrderType.CloseLong ||
            _order2.orderType == OrderType.CloseShort
        ) {
            if (_order2.minMaturityTime != _order2.maxMaturityTime) {
                revert InvalidMaturityTime();
            }
        }

        // Check that the destination is not the zero address.
        if (
            _order1.options.destination == address(0) ||
            _order2.options.destination == address(0)
        ) {
            revert InvalidDestination();
        }

        // Hash orders.
        order1Hash = hashOrderIntent(_order1);
        order2Hash = hashOrderIntent(_order2);

        // Check if orders are fully executed.
        if (
            orderAmountsUsed[order1Hash].bondAmount >= _order1.bondAmount ||
            orderAmountsUsed[order1Hash].fundAmount >= _order1.fundAmount
        ) {
            revert AlreadyFullyExecuted();
        }
        if (
            orderAmountsUsed[order2Hash].bondAmount >= _order2.bondAmount ||
            orderAmountsUsed[order2Hash].fundAmount >= _order2.fundAmount
        ) {
            revert AlreadyFullyExecuted();
        }

        // Check if orders are cancelled.
        if (isCancelled[order1Hash] || isCancelled[order2Hash]) {
            revert AlreadyCancelled();
        }

        // Verify signatures.
        if (
            !verifySignature(order1Hash, _order1.signature, _order1.trader) ||
            !verifySignature(order2Hash, _order2.signature, _order2.trader)
        ) {
            revert InvalidSignature();
        }
    }

    /// @dev Validates the maker and taker orders. This function has shrinked
    ///      logic from the _validateOrdersNoTaker function, as the taker order
    ///      is only a minimal sufficient struct created by the frontend, with
    ///      some fields being faulty values.
    /// @param _makerOrder The maker order to validate.
    /// @param _takerOrder The taker order to validate.
    /// @return makerOrderHash The hash of the maker order.
    function _validateOrdersWithTaker(
        OrderIntent calldata _makerOrder,
        OrderIntent calldata _takerOrder
    ) internal view returns (bytes32 makerOrderHash) {
        // Verify the maker's counterparty is the taker.
        if (
            (_makerOrder.counterparty != address(0) &&
                _makerOrder.counterparty != _takerOrder.trader)
        ) {
            revert InvalidCounterparty();
        }

        // Check expiry.
        if (_makerOrder.expiry <= block.timestamp) {
            revert AlreadyExpired();
        }

        // Verify settlement asset.
        // @dev TODO: only supporting both true or both false for now.
        //      Supporting mixed asBase values needs code changes on the Hyperdrive
        //      instances.
        if (_makerOrder.options.asBase != _takerOrder.options.asBase) {
            revert InvalidSettlementAsset();
        }

        // Verify valid maturity time.
        if (
            _makerOrder.minMaturityTime > _makerOrder.maxMaturityTime ||
            _takerOrder.minMaturityTime > _takerOrder.maxMaturityTime
        ) {
            revert InvalidMaturityTime();
        }

        // For the close order, minMaturityTime must equal maxMaturityTime.
        if (
            _makerOrder.orderType == OrderType.CloseLong ||
            _makerOrder.orderType == OrderType.CloseShort
        ) {
            if (_makerOrder.minMaturityTime != _makerOrder.maxMaturityTime) {
                revert InvalidMaturityTime();
            }
        }
        if (
            _takerOrder.orderType == OrderType.CloseLong ||
            _takerOrder.orderType == OrderType.CloseShort
        ) {
            if (_takerOrder.minMaturityTime != _takerOrder.maxMaturityTime) {
                revert InvalidMaturityTime();
            }
        }

        // Check that the destination is not the zero address.
        if (
            _makerOrder.options.destination == address(0) ||
            _takerOrder.options.destination == address(0)
        ) {
            revert InvalidDestination();
        }

        // Hash the order.
        makerOrderHash = hashOrderIntent(_makerOrder);

        // Check if the maker order is fully executed.
        if (
            orderAmountsUsed[makerOrderHash].bondAmount >=
            _makerOrder.bondAmount ||
            orderAmountsUsed[makerOrderHash].fundAmount >=
            _makerOrder.fundAmount
        ) {
            revert AlreadyFullyExecuted();
        }

        // Check if the maker order is cancelled.
        if (isCancelled[makerOrderHash]) {
            revert AlreadyCancelled();
        }

        // Verify the maker's signature.
        if (
            !verifySignature(
                makerOrderHash,
                _makerOrder.signature,
                _makerOrder.trader
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
    ) internal view returns (uint256 bondMatchAmount) {
        OrderAmounts memory amounts1 = orderAmountsUsed[_order1Hash];
        OrderAmounts memory amounts2 = orderAmountsUsed[_order2Hash];

        uint256 order1BondAmount = _order1.bondAmount - amounts1.bondAmount;
        uint256 order2BondAmount = _order2.bondAmount - amounts2.bondAmount;

        bondMatchAmount = order1BondAmount.min(order2BondAmount);
    }

    /// @dev Handles the minting of matching positions.
    /// @param _longOrder The order for opening a long position.
    /// @param _shortOrder The order for opening a short position.
    /// @param _fundTokenAmountLongOrder The amount of fund tokens from the long
    ///        order.
    /// @param _fundTokenAmountShortOrder The amount of fund tokens from the short
    ///        order.
    /// @param _cost The total cost of the operation.
    /// @param _bondMatchAmount The amount of bonds to mint.
    /// @param _fundToken The fund token being used.
    /// @param _hyperdrive The Hyperdrive contract instance.
    /// @return The amount of bonds minted.
    function _handleMint(
        OrderIntent calldata _longOrder,
        OrderIntent calldata _shortOrder,
        uint256 _fundTokenAmountLongOrder,
        uint256 _fundTokenAmountShortOrder,
        uint256 _cost,
        uint256 _bondMatchAmount,
        ERC20 _fundToken,
        IHyperdrive _hyperdrive
    ) internal returns (uint256) {
        // Transfer fund tokens from long trader.
        _fundToken.safeTransferFrom(
            _longOrder.trader,
            address(this),
            _fundTokenAmountLongOrder
        );

        // Transfer fund tokens from short trader.
        _fundToken.safeTransferFrom(
            _shortOrder.trader,
            address(this),
            _fundTokenAmountShortOrder
        );

        // Approve Hyperdrive.
        // @dev Use balanceOf to get the total amount of fund tokens instead of
        //      summing up the two amounts, in order to open the door for any
        //      potential donation to help match orders.
        uint256 totalFundTokenAmount = _fundToken.balanceOf(address(this));
        uint256 fundTokenAmountToUse = _cost + TOKEN_AMOUNT_BUFFER;
        if (totalFundTokenAmount < fundTokenAmountToUse) {
            revert InsufficientFunding();
        }

        // @dev Add 1 wei of approval so that the storage slot stays hot.
        _fundToken.forceApprove(address(_hyperdrive), fundTokenAmountToUse + 1);

        // Create PairOptions.
        IHyperdrive.PairOptions memory pairOptions = IHyperdrive.PairOptions({
            longDestination: _longOrder.options.destination,
            shortDestination: _shortOrder.options.destination,
            asBase: _longOrder.options.asBase,
            extraData: ""
        });

        // Calculate minVaultSharePrice.
        // @dev Take the larger of the two minVaultSharePrice as the min guard
        //      price to prevent slippage, so that it satisfies both orders.
        uint256 minVaultSharePrice = _longOrder.minVaultSharePrice.max(
            _shortOrder.minVaultSharePrice
        );

        // Mint matching positions.
        (, uint256 bondAmount) = _hyperdrive.mint(
            fundTokenAmountToUse,
            _bondMatchAmount,
            minVaultSharePrice,
            pairOptions
        );

        // Return the bondAmount.
        return bondAmount;
    }

    /// @dev Handles the burning of matching positions.
    /// @param _longOrder The first order (CloseLong).
    /// @param _shortOrder The second order (CloseShort).
    /// @param _minFundAmountLongOrder The minimum fund amount for the long order.
    /// @param _minFundAmountShortOrder The minimum fund amount for the short order.
    /// @param _bondMatchAmount The amount of bonds to burn.
    /// @param _fundToken The fund token being used.
    /// @param _hyperdrive The Hyperdrive contract instance.
    function _handleBurn(
        OrderIntent calldata _longOrder,
        OrderIntent calldata _shortOrder,
        uint256 _minFundAmountLongOrder,
        uint256 _minFundAmountShortOrder,
        uint256 _bondMatchAmount,
        ERC20 _fundToken,
        IHyperdrive _hyperdrive
    ) internal {
        // Get asset IDs for the long and short positions.
        uint256 longAssetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Long,
            _longOrder.maxMaturityTime
        );
        uint256 shortAssetId = AssetId.encodeAssetId(
            AssetId.AssetIdPrefix.Short,
            _shortOrder.maxMaturityTime
        );

        // This contract needs to take custody of the bonds before burning.
        _hyperdrive.safeTransferFrom(
            _longOrder.trader,
            address(this),
            longAssetId,
            _bondMatchAmount,
            ""
        );
        _hyperdrive.safeTransferFrom(
            _shortOrder.trader,
            address(this),
            shortAssetId,
            _bondMatchAmount,
            ""
        );

        // Calculate minOutput and consider the potential donation to help match
        // orders.
        uint256 minOutput = (_minFundAmountLongOrder +
            _minFundAmountShortOrder) > _fundToken.balanceOf(address(this))
            ? _minFundAmountLongOrder +
                _minFundAmountShortOrder -
                _fundToken.balanceOf(address(this))
            : 0;

        // Stack cycling to avoid stack-too-deep.
        OrderIntent calldata longOrder = _longOrder;
        OrderIntent calldata shortOrder = _shortOrder;

        // Burn the matching positions.
        _hyperdrive.burn(
            longOrder.maxMaturityTime,
            _bondMatchAmount,
            minOutput,
            IHyperdrive.Options({
                destination: address(this),
                asBase: longOrder.options.asBase,
                extraData: ""
            })
        );

        // Transfer proceeds to traders.
        _fundToken.safeTransfer(
            longOrder.options.destination,
            _minFundAmountLongOrder
        );
        _fundToken.safeTransfer(
            shortOrder.options.destination,
            _minFundAmountShortOrder
        );
    }

    /// @dev Handles the transfer of positions between traders.
    /// @param _openOrder The order for opening a position.
    /// @param _closeOrder The order for closing a position.
    /// @param _fundTokenAmountOpenOrder The amount of fund tokens from the
    ///        open order.
    /// @param _minFundAmountCloseOrder The minimum fund amount for the close
    ///        order.
    /// @param _bondMatchAmount The amount of bonds to transfer.
    /// @param _fundToken The fund token being used.
    /// @param _hyperdrive The Hyperdrive contract instance.
    function _handleTransfer(
        OrderIntent calldata _openOrder,
        OrderIntent calldata _closeOrder,
        uint256 _fundTokenAmountOpenOrder,
        uint256 _minFundAmountCloseOrder,
        uint256 _bondMatchAmount,
        ERC20 _fundToken,
        IHyperdrive _hyperdrive
    ) internal {
        // Get asset ID for the position.
        uint256 assetId;
        if (_openOrder.orderType == OrderType.OpenLong) {
            assetId = AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.Long,
                _closeOrder.maxMaturityTime
            );
        } else {
            assetId = AssetId.encodeAssetId(
                AssetId.AssetIdPrefix.Short,
                _closeOrder.maxMaturityTime
            );
        }

        // Transfer the position from the close trader to the open trader.
        _hyperdrive.safeTransferFrom(
            _closeOrder.trader,
            _openOrder.options.destination,
            assetId,
            _bondMatchAmount,
            ""
        );

        // Transfer fund tokens from open trader to the close trader.
        // @dev Considering this address may hold donated fund tokens, so we
        //      transfer all the _fundTokenAmountOpenOrder to this contract
        //      first, then transfer the needed amount to the close trader.
        _fundToken.safeTransferFrom(
            _openOrder.trader,
            address(this),
            _fundTokenAmountOpenOrder
        );
        _fundToken.safeTransfer(
            _closeOrder.options.destination,
            _minFundAmountCloseOrder
        );
    }

    /// @dev Gets the most recent checkpoint time.
    /// @param _checkpointDuration The duration of the checkpoint.
    /// @return latestCheckpoint The latest checkpoint.
    function _latestCheckpoint(
        uint256 _checkpointDuration
    ) internal view returns (uint256 latestCheckpoint) {
        latestCheckpoint = HyperdriveMath.calculateCheckpointTime(
            block.timestamp,
            _checkpointDuration
        );
    }

    /// @dev Calculates the cost and parameters for minting positions.
    /// @param _hyperdrive The Hyperdrive contract instance.
    /// @param _bondMatchAmount The amount of bonds to mint.
    /// @return maturityTime The maturity time for new positions.
    /// @return cost The total cost including fees.
    function _calculateMintCost(
        IHyperdrive _hyperdrive,
        uint256 _bondMatchAmount
    ) internal view returns (uint256 maturityTime, uint256 cost) {
        // Get pool configuration.
        IHyperdrive.PoolConfig memory config = _hyperdrive.getPoolConfig();

        // Calculate checkpoint and maturity time.
        uint256 latestCheckpoint = _latestCheckpoint(config.checkpointDuration);
        maturityTime = latestCheckpoint + config.positionDuration;

        // Get vault share prices.
        // @dev TODO: there is another way to get the info without calling
        //      getPoolInfo()?
        uint256 vaultSharePrice = _hyperdrive.getPoolInfo().vaultSharePrice;
        uint256 openVaultSharePrice = _hyperdrive
            .getCheckpoint(latestCheckpoint)
            .vaultSharePrice;
        if (openVaultSharePrice == 0) {
            openVaultSharePrice = vaultSharePrice;
        }

        // Calculate the required fund amount.
        // NOTE: Round the required fund amount up to overestimate the cost.
        cost = _bondMatchAmount.mulDivUp(
            vaultSharePrice.max(openVaultSharePrice),
            openVaultSharePrice
        );

        // Add flat fee.
        // NOTE: Round the flat fee calculation up to match other flows.
        uint256 flatFee = _bondMatchAmount.mulUp(config.fees.flat);
        cost += flatFee;

        // Add governance fee.
        // NOTE: Round the governance fee calculation down to match other flows.
        uint256 governanceFee = 2 * flatFee.mulDown(config.fees.governanceLP);
        cost += governanceFee;
    }

    /// @dev Updates either the bond amount or fund amount used for a given order.
    /// @param orderHash The hash of the order.
    /// @param amount The amount to add.
    /// @param updateBond If true, updates bond amount; if false, updates fund
    ///        amount.
    function _updateOrderAmount(
        bytes32 orderHash,
        uint256 amount,
        bool updateBond
    ) internal {
        OrderAmounts memory amounts = orderAmountsUsed[orderHash];

        if (updateBond) {
            // Check for overflow before casting to uint128
            if (amounts.bondAmount + amount > type(uint128).max) {
                revert AmountOverflow();
            }
            orderAmountsUsed[orderHash] = OrderAmounts({
                bondAmount: uint128(amounts.bondAmount + amount),
                fundAmount: amounts.fundAmount
            });
        } else {
            // Check for overflow before casting to uint128.
            if (amounts.fundAmount + amount > type(uint128).max) {
                revert AmountOverflow();
            }
            orderAmountsUsed[orderHash] = OrderAmounts({
                bondAmount: amounts.bondAmount,
                fundAmount: uint128(amounts.fundAmount + amount)
            });
        }
    }
}
