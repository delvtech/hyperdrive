// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IHyperdrive } from "./IHyperdrive.sol";
import { ISwapRouter } from "./ISwapRouter.sol";

/// @title IUniV3Zap
/// @author DELV
/// @notice The interface for the UniV3Zap contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
interface IUniV3Zap {
    /// Errors ///

    /// @notice Thrown when attempting to zap to an invalid input token.
    error InvalidInputToken();

    /// @notice Thrown when attempting to zap to an invalid output token.
    error InvalidOutputToken();

    /// @notice Thrown when attempting to zap to an invalid recipient.
    error InvalidRecipient();

    /// @notice Thrown when attempting to zap with an invalid source amount. If
    ///         the source asset doesn't needs to be wrapped, this needs to be
    ///         the same as the swap's input amount.
    error InvalidSourceAmount();

    /// @notice Thrown when attempting to zap with an invalid source asset. If
    ///         the source asset needs to be wrapped, this shouldn't be the same
    ///         address as the input token to the swap. Otherwise, they should
    ///         be the same.
    error InvalidSourceAsset();

    /// @notice Thrown when attempting to zap from an asset to itself. This
    ///         protects users from swaps that could only lead them to incur
    ///         losses through fees and slippage.
    error InvalidSwap();

    /// @notice Thrown when receiving ether outside of an zap.
    error InvalidTransfer();

    /// @notice Thrown when ether is sent to an instance that doesn't accept
    ///         ether as a deposit asset.
    error NotPayable();

    /// @notice Thrown when we should be wrapping assets, but the zap isn't
    ///         configured to wrap.
    error ShouldWrapAssets();

    /// @notice Thrown when an ether transfer fails.
    error TransferFailed();

    /// Structs ///

    /// @dev The options parameter provided to all of the functions that zap
    ///      funds into Hyperdrive.
    struct ZapInOptions {
        /// @dev The Uniswap swap parameters to use when swapping assets to the
        ///      deposit asset.
        ISwapRouter.ExactInputParams swapParams;
        /// @dev In most cases, this should be equal to the input token of the
        ///      swap. In some cases, this will be a rebasing token like stETH
        ///      that needs to be wrapped to make it suitable for swapping on
        ///      Uniswap.
        address sourceAsset;
        /// @dev The amount of source tokens that should be swapped. In most
        ///      cases, this should be equal to the `swapParams.amountIn`, but
        ///      in the case of wrapped tokens, this amount will supersede that
        ///      quantity.
        uint256 sourceAmount;
        /// @dev A flag that indicates whether or not the source token should
        ///      be wrapped into the input token. Uniswap v3 demands complete
        ///      precision on the input token amounts, which makes it hard to
        ///      work with rebasing tokens that have imprecise transfer
        ///      functions. Wrapping tokens provides a workaround for these
        ///      issues.
        bool shouldWrap;
        /// @dev A flag that indicates whether or not the Hyperdrive vault
        ///      shares token is a vault shares token. This is used to ensure
        ///      that the input into Hyperdrive properly handles rebasing tokens.
        bool isRebasing;
    }

    /// Metadata ///

    /// @notice Returns the name of this zap.
    /// @return The name of this zap.
    function name() external view returns (string memory);

    /// @notice Returns the kind of this zap.
    /// @return The kind of this zap.
    function kind() external view returns (string memory);

    /// @notice Returns the version of this zap.
    /// @return The version of this zap.
    function version() external view returns (string memory);

    /// LPs ///

    /// @notice Executes a swap on Uniswap and uses the proceeds to add
    ///         liquidity on Hyperdrive.
    /// @param _hyperdrive The Hyperdrive pool to open the long on.
    /// @param _minLpSharePrice The minimum LP share price the LP is willing
    ///        to accept for their shares. LPs incur negative slippage when
    ///        adding liquidity if there is a net curve position in the market,
    ///        so this allows LPs to protect themselves from high levels of
    ///        slippage. The units of this quantity are either base or vault
    ///        shares, depending on the value of `_options.asBase`.
    /// @param _minApr The minimum APR at which the LP is willing to supply.
    /// @param _maxApr The maximum APR at which the LP is willing to supply.
    /// @param _hyperdriveOptions The options that configure how the Hyperdrive
    ///        operation is settled.
    /// @param _zapInOptions The options that configure how the zap will be
    ///        settled.
    /// @return lpShares The LP shares received by the LP.
    function addLiquidityZap(
        IHyperdrive _hyperdrive,
        uint256 _minLpSharePrice,
        uint256 _minApr,
        uint256 _maxApr,
        IHyperdrive.Options calldata _hyperdriveOptions,
        IUniV3Zap.ZapInOptions calldata _zapInOptions
    ) external payable returns (uint256 lpShares);

    /// @notice Removes liquidity on Hyperdrive and converts the proceeds to the
    ///         traders preferred asset by executing a swap on Uniswap v3.
    /// @param _hyperdrive The Hyperdrive pool to open the long on.
    /// @param _lpShares The LP shares to burn.
    /// @param _minOutputPerShare The minimum amount the LP expects to receive
    ///        for each withdrawal share that is burned. The units of this
    ///        quantity are either base or vault shares, depending on the value
    ///        of `_options.asBase`.
    /// @param _options The options that configure how the operation is settled.
    /// @param _swapParams The Uniswap swap parameters for a multi-hop fill.
    /// @param _shouldWrap A flag indicating whether or not the proceeds need to
    ///        be wrapped.
    /// @return proceeds The proceeds of removing liquidity. These proceeds will
    ///         be in units determined by the Uniswap swap parameters.
    /// @return withdrawalShares The base that the LP receives buys out some of
    ///         their LP shares, but it may not be sufficient to fully buy the
    ///         LP out. In this case, the LP receives withdrawal shares equal in
    ///         value to the present value they are owed. As idle capital
    ///         becomes available, the pool will buy back these shares.
    function removeLiquidityZap(
        IHyperdrive _hyperdrive,
        uint256 _lpShares,
        uint256 _minOutputPerShare,
        IHyperdrive.Options calldata _options,
        ISwapRouter.ExactInputParams calldata _swapParams,
        bool _shouldWrap
    ) external returns (uint256 proceeds, uint256 withdrawalShares);

    /// @notice Redeem withdrawal shares on Hyperdrive and converts the proceeds
    ///         to the traders preferred asset by executing a swap on Uniswap
    ///         v3.
    /// @param _hyperdrive The Hyperdrive pool to open the long on.
    /// @param _withdrawalShares The withdrawal shares to redeem.
    /// @param _minOutputPerShare The minimum amount the LP expects to
    ///        receive for each withdrawal share that is burned. The units of
    ///        this quantity are either base or vault shares, depending on the
    ///        value of `_options.asBase`.
    /// @param _options The options that configure how the operation is settled.
    /// @param _swapParams The Uniswap swap parameters for a multi-hop fill.
    /// @param _shouldWrap A flag indicating whether or not the proceeds need to
    ///        be wrapped.
    /// @return proceeds The proceeds of redeeming withdrawal shares. These
    ///         proceeds will be in units determined by the Uniswap swap
    ///         parameters.
    /// @return withdrawalSharesRedeemed The amount of withdrawal shares that
    ///         were redeemed.
    function redeemWithdrawalSharesZap(
        IHyperdrive _hyperdrive,
        uint256 _withdrawalShares,
        uint256 _minOutputPerShare,
        IHyperdrive.Options calldata _options,
        ISwapRouter.ExactInputParams calldata _swapParams,
        bool _shouldWrap
    ) external returns (uint256 proceeds, uint256 withdrawalSharesRedeemed);

    /// Longs ///

    /// @notice Executes a swap on Uniswap and uses the proceeds to open a long
    ///         on Hyperdrive.
    /// @param _hyperdrive The Hyperdrive pool to open the long on.
    /// @param _minOutput The minimum number of bonds to receive.
    /// @param _minVaultSharePrice The minimum vault share price at which to
    ///        open the long. This allows traders to protect themselves from
    ///        opening a long in a checkpoint where negative interest has
    ///        accrued.
    /// @param _hyperdriveOptions The options that configure how the Hyperdrive
    ///        operation is settled.
    /// @param _zapInOptions The options that configure how the zap will be
    ///        settled.
    /// @return maturityTime The maturity time of the bonds.
    /// @return longAmount The amount of bonds the trader received.
    function openLongZap(
        IHyperdrive _hyperdrive,
        uint256 _minOutput,
        uint256 _minVaultSharePrice,
        IHyperdrive.Options calldata _hyperdriveOptions,
        IUniV3Zap.ZapInOptions calldata _zapInOptions
    ) external payable returns (uint256 maturityTime, uint256 longAmount);

    /// @notice Closes a long on Hyperdrive and converts the proceeds to the
    ///         traders preferred asset by executing a swap on Uniswap v3.
    /// @param _hyperdrive The Hyperdrive pool to open the long on.
    /// @param _maturityTime The maturity time of the long.
    /// @param _bondAmount The amount of longs to close.
    /// @param _minOutput The minimum proceeds the trader will accept. The units
    ///        of this quantity are either base or vault shares, depending on
    ///        the value of `_options.asBase`.
    /// @param _options The options that configure how the Hyperdrive trade is
    ///        settled.
    /// @param _swapParams The Uniswap swap parameters for a multi-hop fill.
    /// @param _shouldWrap A flag indicating whether or not the proceeds need to
    ///        be wrapped.
    /// @return proceeds The proceeds of closing the long. These proceeds will
    ///         be in units determined by the Uniswap swap parameters.
    function closeLongZap(
        IHyperdrive _hyperdrive,
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        IHyperdrive.Options calldata _options,
        ISwapRouter.ExactInputParams calldata _swapParams,
        bool _shouldWrap
    ) external returns (uint256 proceeds);

    /// Shorts ///

    /// @notice Executes a swap on Uniswap and uses the proceeds to open a short
    ///         on Hyperdrive.
    /// @param _hyperdrive The Hyperdrive pool to open the long on.
    /// @param _maxDeposit The most the user expects to deposit for this trade.
    ///        The units of this quantity are either base or vault shares,
    ///        depending on the value of `_options.asBase`.
    /// @param _minVaultSharePrice The minimum vault share price at which to open
    ///        the short. This allows traders to protect themselves from opening
    ///        a short in a checkpoint where negative interest has accrued.
    /// @param _hyperdriveOptions The options that configure how the Hyperdrive
    ///        operation is settled.
    /// @param _zapInOptions The options that configure how the zap will be
    ///        settled.
    /// @return maturityTime The maturity time of the bonds.
    /// @return deposit The amount the user deposited for this trade. The units
    ///         of this quantity are either base or vault shares, depending on
    ///         the value of `_options.asBase`.
    function openShortZap(
        IHyperdrive _hyperdrive,
        uint256 _bondAmount,
        uint256 _maxDeposit,
        uint256 _minVaultSharePrice,
        IHyperdrive.Options calldata _hyperdriveOptions,
        IUniV3Zap.ZapInOptions calldata _zapInOptions
    ) external payable returns (uint256 maturityTime, uint256 deposit);

    /// @notice Closes a short on Hyperdrive and converts the proceeds to the
    ///         traders preferred asset by executing a swap on Uniswap v3.
    /// @param _hyperdrive The Hyperdrive pool to open the long on.
    /// @param _maturityTime The maturity time of the short.
    /// @param _bondAmount The amount of shorts to close.
    /// @param _minOutput The minimum output of this trade. The units of this
    ///        quantity are either base or vault shares, depending on the value
    ///        of `_options.asBase`.
    /// @param _options The options that configure how the Hyperdrive trade is
    ///        settled.
    /// @param _swapParams The Uniswap swap parameters for a multi-hop fill.
    /// @param _shouldWrap A flag indicating whether or not the proceeds need to
    ///        be wrapped.
    /// @return proceeds The proceeds of closing the short. These proceeds will
    ///         be in units determined by the Uniswap swap parameters.
    function closeShortZap(
        IHyperdrive _hyperdrive,
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        IHyperdrive.Options calldata _options,
        ISwapRouter.ExactInputParams calldata _swapParams,
        bool _shouldWrap
    ) external returns (uint256 proceeds);

    /// Getters ///

    /// @notice Returns the Uniswap swap router.
    /// @return The Uniswap swap router.
    function swapRouter() external view returns (ISwapRouter);
}
