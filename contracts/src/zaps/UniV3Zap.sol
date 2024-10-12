// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "openzeppelin/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";
import { ILido } from "../interfaces/ILido.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { ISwapRouter } from "../interfaces/ISwapRouter.sol";
import { IUniV3Zap } from "../interfaces/IUniV3Zap.sol";
import { IWETH } from "../interfaces/IWETH.sol";
import { IWrappedERC20 } from "../interfaces/IWrappedERC20.sol";
import { AssetId } from "../libraries/AssetId.sol";
import { ETH, UNI_V3_ZAP_KIND, VERSION } from "../libraries/Constants.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { UniV3Path } from "../libraries/UniV3Path.sol";

/// @title UniV3Zap
/// @author DELV
/// @notice A zap contract that uses Uniswap v3 to execute swaps before or after
///         interacting with Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract UniV3Zap is IUniV3Zap, ReentrancyGuard {
    using FixedPointMath for uint256;
    using SafeERC20 for ERC20;
    using UniV3Path for bytes;

    /// @dev We can assume that almost all Hyperdrive deployments have the
    ///      `convertToBase` and `convertToShares` functions, but there is
    ///      one legacy sDAI pool that was deployed before these functions
    ///      were written. We explicitly special case conversions for this
    ///      pool.
    address internal constant LEGACY_SDAI_HYPERDRIVE =
        address(0x324395D5d835F84a02A75Aa26814f6fD22F25698);

    /// @notice We can assume that almost all Hyperdrive deployments have the
    ///         `convertToBase` and `convertToShares` functions, but there is
    ///         one legacy stETH pool that was deployed before these functions
    ///         were written. We explicitly special case conversions for this
    ///         pool.
    address internal constant LEGACY_STETH_HYPERDRIVE =
        address(0xd7e470043241C10970953Bd8374ee6238e77D735);

    /// @notice The Uniswap swap router.
    ISwapRouter public immutable swapRouter;

    /// @notice The wrapped ether address.
    IWETH public immutable weth;

    /// @notice The name of this zap.
    string public name;

    /// @notice The kind of this zap.
    string public constant kind = UNI_V3_ZAP_KIND;

    /// @notice The version of this zap.
    string public constant version = VERSION;

    /// @notice Instantiates the zap contract.
    /// @param _name The name of this zap contract.
    /// @param _swapRouter The uniswap swap router.
    /// @param _weth The wrapped ether address.
    constructor(string memory _name, ISwapRouter _swapRouter, IWETH _weth) {
        name = _name;
        swapRouter = _swapRouter;
        weth = _weth;
    }

    /// Receive ///

    /// @notice Allows ETH to be received within the context of a zap.
    /// @dev This fails if it isn't called within the context of a zap to reduce
    ///      the likelihood of users sending ether to this contract accidentally.
    receive() external payable {
        // Ensures that the zap is receiving ether inside the context of another
        // call. This means that the ether transfer should be the result of a
        // Hyperdrive trade or unwrapping WETH.
        if (!_reentrancyGuardEntered()) {
            revert InvalidTransfer();
        }
    }

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
    ) external payable nonReentrant returns (uint256 lpShares) {
        // Validate the zap parameters.
        bool shouldConvertToETH = _validateZapIn(
            _hyperdrive,
            _hyperdriveOptions,
            _zapInOptions
        );

        // Zap the funds that will be used to add liquidity and approve the pool
        // to spend these funds.
        uint256 proceeds = _zapIn(_zapInOptions, shouldConvertToETH);

        // If the deposit isn't in ETH, we need to set an approval on Hyperdrive.
        if (!shouldConvertToETH) {
            // NOTE: We increase the required approval amount by 1 wei so that the
            // pool ends with an approval of 1 wei. This makes future approvals
            // cheaper by keeping the storage slot warm.
            ERC20(_zapInOptions.swapParams.path.tokenOut()).forceApprove(
                address(_hyperdrive),
                proceeds + 1
            );
        }

        // Add liquidity using the proceeds of the trade. If the vault shares
        // token is a rebasing token, the proceeds amount needs to be converted
        // to vault shares.
        if (!_hyperdriveOptions.asBase && _zapInOptions.isRebasing) {
            proceeds = _convertToShares(_hyperdrive, proceeds);
        }
        uint256 value = shouldConvertToETH ? proceeds : 0;
        lpShares = _hyperdrive.addLiquidity{ value: value }(
            proceeds,
            _minLpSharePrice,
            _minApr,
            _maxApr,
            _hyperdriveOptions
        );

        return lpShares;
    }

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
    )
        external
        nonReentrant
        returns (uint256 proceeds, uint256 withdrawalShares)
    {
        // Validate the zap parameters.
        address proceedsAsset = _validateZapOut(
            _hyperdrive,
            _options,
            _swapParams,
            _shouldWrap
        );

        // Take custody of the LP shares.
        _hyperdrive.transferFrom(
            AssetId._LP_ASSET_ID,
            msg.sender,
            address(this),
            _lpShares
        );

        // Remove the liquidity, zap the proceeds into the target asset, and
        // send them to the LP.
        //
        // NOTE: We zap out the contract's entire balance of the swap's input
        // token. This ensures that we properly handle vault shares tokens that
        // rebase and also ensures that this contract doesn't end up with stuck
        // tokens. As a consequence, we don't need the output value of closing
        // the long position.
        (, withdrawalShares) = _hyperdrive.removeLiquidity(
            _lpShares,
            _minOutputPerShare,
            _options
        );
        proceeds = _zapOut(_swapParams, proceedsAsset, _shouldWrap);

        return (proceeds, withdrawalShares);
    }

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
    )
        external
        nonReentrant
        returns (uint256 proceeds, uint256 withdrawalSharesRedeemed)
    {
        // Validate the zap parameters.
        address proceedsAsset = _validateZapOut(
            _hyperdrive,
            _options,
            _swapParams,
            _shouldWrap
        );

        // Take custody of the LP shares.
        _hyperdrive.transferFrom(
            AssetId._WITHDRAWAL_SHARE_ASSET_ID,
            msg.sender,
            address(this),
            _withdrawalShares
        );

        // Redeem the withdrawal shares, zap the proceeds into the target asset,
        // and send them to the LP.
        //
        // NOTE: We zap out the contract's entire balance of the swap's input
        // token. This ensures that we properly handle vault shares tokens that
        // rebase and also ensures that this contract doesn't end up with stuck
        // tokens. As a consequence, we don't need the output value of closing
        // the long position.
        (, withdrawalSharesRedeemed) = _hyperdrive.redeemWithdrawalShares(
            _withdrawalShares,
            _minOutputPerShare,
            _options
        );
        proceeds = _zapOut(_swapParams, proceedsAsset, _shouldWrap);

        return (proceeds, withdrawalSharesRedeemed);
    }

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
    )
        external
        payable
        nonReentrant
        returns (uint256 maturityTime, uint256 longAmount)
    {
        // Validate the zap parameters.
        bool shouldConvertToETH = _validateZapIn(
            _hyperdrive,
            _hyperdriveOptions,
            _zapInOptions
        );

        // Zap the funds that will be used to open the long and approve the pool
        // to spend these funds.
        uint256 proceeds = _zapIn(_zapInOptions, shouldConvertToETH);

        // If the deposit isn't in ETH, we need to set an approval on Hyperdrive.
        if (!shouldConvertToETH) {
            // NOTE: We increase the required approval amount by 1 wei so that the
            // pool ends with an approval of 1 wei. This makes future approvals
            // cheaper by keeping the storage slot warm.
            ERC20(_zapInOptions.swapParams.path.tokenOut()).forceApprove(
                address(_hyperdrive),
                proceeds + 1
            );
        }

        // Open a long using the proceeds of the trade. If the vault shares
        // token is a rebasing token, the proceeds amount needs to be converted
        // to vault shares.
        if (!_hyperdriveOptions.asBase && _zapInOptions.isRebasing) {
            proceeds = _convertToShares(_hyperdrive, proceeds);
        }
        uint256 value = shouldConvertToETH ? proceeds : 0;
        (maturityTime, longAmount) = _hyperdrive.openLong{ value: value }(
            proceeds,
            _minOutput,
            _minVaultSharePrice,
            _hyperdriveOptions
        );

        return (maturityTime, longAmount);
    }

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
    ) external nonReentrant returns (uint256 proceeds) {
        // Validate the zap parameters.
        address proceedsAsset = _validateZapOut(
            _hyperdrive,
            _options,
            _swapParams,
            _shouldWrap
        );

        // Take custody of the long position.
        _hyperdrive.transferFrom(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, _maturityTime),
            msg.sender,
            address(this),
            _bondAmount
        );

        // Close the long, zap the proceeds into the target asset, and send
        // them to the trader.
        //
        // NOTE: We zap out the contract's entire balance of the swap's input
        // token. This ensures that we properly handle vault shares tokens that
        // rebase and also ensures that this contract doesn't end up with stuck
        // tokens. As a consequence, we don't need the output value of closing
        // the long position.
        _hyperdrive.closeLong(_maturityTime, _bondAmount, _minOutput, _options);
        proceeds = _zapOut(_swapParams, proceedsAsset, _shouldWrap);

        return proceeds;
    }

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
    )
        external
        payable
        nonReentrant
        returns (uint256 maturityTime, uint256 deposit)
    {
        // Validate the zap parameters.
        bool shouldConvertToETH = _validateZapIn(
            _hyperdrive,
            _hyperdriveOptions,
            _zapInOptions
        );

        // Zap the funds that will be used to open the long and approve the pool
        // to spend these funds.
        uint256 proceeds = _zapIn(_zapInOptions, shouldConvertToETH);

        // If the deposit isn't in ETH, we need to set an approval on Hyperdrive.
        address tokenOut = _zapInOptions.swapParams.path.tokenOut();
        if (!shouldConvertToETH) {
            // NOTE: We increase the required approval amount by 1 wei so that the
            // pool ends with an approval of 1 wei. This makes future approvals
            // cheaper by keeping the storage slot warm.
            ERC20(tokenOut).forceApprove(address(_hyperdrive), proceeds + 1);
        }

        // Open a short using the proceeds of the trade.
        uint256 value = shouldConvertToETH ? proceeds : 0;
        (maturityTime, deposit) = _hyperdrive.openShort{ value: value }(
            _bondAmount,
            _maxDeposit,
            _minVaultSharePrice,
            _hyperdriveOptions
        );

        // If the deposit was in ETH and capital is left after the trade, send
        // it back to the trader.
        if (shouldConvertToETH) {
            uint256 balance = address(this).balance;
            if (balance > 0) {
                (bool success, ) = msg.sender.call{ value: balance }("");
                if (!success) {
                    revert TransferFailed();
                }
            }
        }
        // Otherwise, if the deposit asset was an ERC20 token and capital is
        // left after the trade, send it back to the trader.
        else {
            uint256 balance = IERC20(tokenOut).balanceOf(address(this));
            if (balance > 0) {
                ERC20(tokenOut).safeTransfer(msg.sender, balance);
            }
        }

        return (maturityTime, deposit);
    }

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
    ) external nonReentrant returns (uint256 proceeds) {
        // Validate the zap parameters.
        address proceedsAsset = _validateZapOut(
            _hyperdrive,
            _options,
            _swapParams,
            _shouldWrap
        );

        // Take custody of the short position.
        _hyperdrive.transferFrom(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Short, _maturityTime),
            msg.sender,
            address(this),
            _bondAmount
        );

        // Close the short, zap the proceeds into the target asset, and send
        // them to the trader.
        //
        // NOTE: We zap out the contract's entire balance of the swap's input
        // token. This ensures that we properly handle vault shares tokens that
        // rebase and also ensures that this contract doesn't end up with stuck
        // tokens. As a consequence, we don't need the output value of closing
        // the long position.
        _hyperdrive.closeShort(
            _maturityTime,
            _bondAmount,
            _minOutput,
            _options
        );
        proceeds = _zapOut(_swapParams, proceedsAsset, _shouldWrap);

        return proceeds;
    }

    /// Helpers ///

    /// @dev Validate the swap parameters for zapping tokens into Hyperdrive.
    /// @param _hyperdrive The Hyperdrive pool to open the long on.
    /// @param _hyperdriveOptions The options that configure how the Hyperdrive
    ///        operation is settled.
    /// @param _zapInOptions The options for the zap.
    /// @return A flag indicating whether or not the zap's output should be
    ///         converted to ETH.
    function _validateZapIn(
        IHyperdrive _hyperdrive,
        IHyperdrive.Options calldata _hyperdriveOptions,
        IUniV3Zap.ZapInOptions calldata _zapInOptions
    ) internal view returns (bool) {
        // Ensure that the swap recipient is this contract.
        if (_zapInOptions.swapParams.recipient != address(this)) {
            revert InvalidRecipient();
        }

        // Ensure that the input and output tokens of the swap are different.
        // If they are the same, this will fail at best or lead to an
        // unnecessary swap at worst.
        address tokenIn = _zapInOptions.swapParams.path.tokenIn();
        address tokenOut = _zapInOptions.swapParams.path.tokenOut();
        if (tokenIn == tokenOut) {
            revert InvalidSwap();
        }

        // Ensure that the options are properly configured if we are wrapping
        // tokens.
        if (_zapInOptions.shouldWrap) {
            // Ensure that the source asset isn't the same as the input asset.
            if (_zapInOptions.sourceAsset == tokenIn) {
                revert InvalidSourceAsset();
            }

            // If ETH is the source asset, make sure that WETH is specified as
            // the input asset.
            if (_zapInOptions.sourceAsset == ETH && tokenIn != address(weth)) {
                revert InvalidSourceAsset();
            }

            // If ETH is the source asset, make sure that sufficient ETH was
            // sent and that the source amount equals the input amount.
            if (
                _zapInOptions.sourceAsset == ETH &&
                (msg.value < _zapInOptions.sourceAmount ||
                    _zapInOptions.sourceAmount !=
                    _zapInOptions.swapParams.amountIn)
            ) {
                revert InvalidSourceAsset();
            }
        }
        // Ensure that the options are properly configured if we're not wrapping
        // tokens.
        else {
            // Ensure that the source asset is the same as the input asset to the
            // swap.
            if (_zapInOptions.sourceAsset != tokenIn) {
                revert InvalidSourceAsset();
            }

            // Ensure that the source amount is the same as the input amount.
            if (
                _zapInOptions.sourceAmount != _zapInOptions.swapParams.amountIn
            ) {
                revert InvalidSourceAmount();
            }
        }

        // If we're depositing with base, the output token is WETH, and the base
        // token is ETH, we need to convert the WETH proceeds of the zap to ETH
        // before executing the Hyperdrive trade.
        address baseToken = _hyperdrive.baseToken();
        if (
            _hyperdriveOptions.asBase &&
            tokenOut == address(weth) &&
            baseToken == ETH
        ) {
            return true;
        }
        // Ensure that if we're depositing with base that the output token
        // of the zap is the Hyperdrive pool's base token.
        else if (
            _hyperdriveOptions.asBase && tokenOut != _hyperdrive.baseToken()
        ) {
            revert InvalidOutputToken();
        }
        // Ensure that if we're depositing with vault shares that the output
        // token of the zap is the Hyperdrive pool's vault shares token.
        else if (
            !_hyperdriveOptions.asBase &&
            tokenOut != _hyperdrive.vaultSharesToken()
        ) {
            revert InvalidOutputToken();
        }

        return false;
    }

    /// @dev Validate the swap parameters for zapping tokens out of Hyperdrive.
    /// @param _hyperdrive The Hyperdrive pool to open the long on.
    /// @param _hyperdriveOptions The options that configure how the Hyperdrive
    ///        operation is settled.
    /// @param _swapParams The Uniswap swap parameters for a multi-hop fill.
    /// @param _shouldWrap A flag indicating that the Hyperdrive proceeds should
    ///        be wrapped before the swap is made.
    /// @return The asset that will be output by the Hyperdrive operation as
    ///         proceeds.
    function _validateZapOut(
        IHyperdrive _hyperdrive,
        IHyperdrive.Options calldata _hyperdriveOptions,
        ISwapRouter.ExactInputParams memory _swapParams,
        bool _shouldWrap
    ) internal view returns (address) {
        // Ensure that the swap recipient is the sender.
        if (_hyperdriveOptions.destination != address(this)) {
            revert InvalidRecipient();
        }

        // Ensure that the input and output tokens of the swap are different.
        // If they are the same, this will fail at best or lead to an
        // unnecessary swap at worst.
        address tokenIn = _swapParams.path.tokenIn();
        address tokenOut = _swapParams.path.tokenOut();
        if (tokenIn == tokenOut) {
            revert InvalidSwap();
        }

        // If the withdrawal is in base, the proceeds are in the base token.
        // Otherwise, they are in the vault shares token.
        address proceedsAsset;
        if (_hyperdriveOptions.asBase) {
            proceedsAsset = _hyperdrive.baseToken();
        } else {
            proceedsAsset = _hyperdrive.vaultSharesToken();
        }

        // Validate the zap if the proceeds are in ETH.
        if (proceedsAsset == ETH) {
            // Ensure that we are wrapping the proceeds.
            if (!_shouldWrap) {
                revert ShouldWrapAssets();
            }

            // Ensure that the input token is WETH.
            if (tokenIn != address(weth)) {
                revert InvalidInputToken();
            }
        }
        // Validate the other cases.
        else {
            // Ensure that if we aren't wrapping the proceeds that the proceeds
            // asset matches the input token.
            if (!_shouldWrap && proceedsAsset != tokenIn) {
                revert InvalidInputToken();
            }

            // Ensure that if we are wrapping the proceeds that the proceeds
            // asset doesn't match the input token.
            if (_shouldWrap && proceedsAsset == tokenIn) {
                revert InvalidInputToken();
            }
        }

        return proceedsAsset;
    }

    /// @dev Zaps funds into this contract to open positions on Hyperdrive.
    /// @param _zapInOptions The options for the zap.
    /// @param _shouldConvertToETH A flag indicating whether or not the proceeds
    ///        should be converted to ETH.
    /// @return proceeds The amount of assets that were zapped into this
    ///         contract.
    function _zapIn(
        IUniV3Zap.ZapInOptions memory _zapInOptions,
        bool _shouldConvertToETH
    ) internal returns (uint256 proceeds) {
        // If the source token is ETH, we'll pay for the swap directly with ETH.
        uint256 refund;
        uint256 value;
        address tokenIn = _zapInOptions.swapParams.path.tokenIn();
        if (_zapInOptions.sourceAsset == ETH) {
            // Refund the difference between the message value and the input
            // amount to the sender.
            refund = msg.value - _zapInOptions.swapParams.amountIn;

            // Send the input amount of ETH to the swap router.
            value = _zapInOptions.swapParams.amountIn;
        }
        // If the we need to wrap assets for the swap, we'll need to
        // take custody of the source assets, wrap them, and then approve the
        // swap router to spend the wrapped assets.
        else if (_zapInOptions.shouldWrap) {
            // Take custody of the source assets to wrap. The input token is
            // assumed to be the wrapped version of the source token, so we set
            // up an approval on that.
            ERC20(_zapInOptions.sourceAsset).safeTransferFrom(
                msg.sender,
                address(this),
                _zapInOptions.sourceAmount
            );
            // NOTE: We increase the required approval amount by 1 wei so that
            // the input token ends with an approval of 1 wei. This makes future
            // approvals cheaper by keeping the storage slot warm.
            ERC20(_zapInOptions.sourceAsset).forceApprove(
                address(tokenIn),
                _zapInOptions.sourceAmount + 1
            );

            // Wrap the source assets. Then we update the swap parameters so
            // that the swap's input amount is equal to this contract's total
            // balance of the input token. Finally, we set up an approval for
            // the swap router.
            IWrappedERC20(tokenIn).wrap(_zapInOptions.sourceAmount);
            _zapInOptions.swapParams.amountIn = IERC20(tokenIn).balanceOf(
                address(this)
            );
            // NOTE: We increase the required approval amount by 1 wei so that
            // the router ends with an approval of 1 wei. This makes future
            // approvals cheaper by keeping the storage slot warm.
            ERC20(tokenIn).forceApprove(
                address(swapRouter),
                _zapInOptions.swapParams.amountIn + 1
            );

            // Refund all of the ETH sent to the contract.
            refund = msg.value;
        }
        // Otherwise, we just need to take custody of the input assets to the
        // swap.
        else {
            // Take custody of the assets to swap. Then we update the swap
            // parameters so that the swap's input amount is equal to this
            // contract's total balance of the input token. This ensures that
            // stuck tokens from this contract are used.
            ERC20(tokenIn).safeTransferFrom(
                msg.sender,
                address(this),
                _zapInOptions.sourceAmount
            );
            _zapInOptions.swapParams.amountIn = IERC20(tokenIn).balanceOf(
                address(this)
            );

            // Approve the swap router to spend the input tokens.
            //
            // NOTE: We increase the required approval amount by 1 wei so that
            // the router ends with an approval of 1 wei. This makes future
            // approvals cheaper by keeping the storage slot warm.
            ERC20(tokenIn).forceApprove(
                address(swapRouter),
                _zapInOptions.swapParams.amountIn + 1
            );

            // Refund all of the ETH sent to the contract.
            refund = msg.value;
        }

        // Execute the Uniswap trade.
        proceeds = swapRouter.exactInput{ value: value }(
            _zapInOptions.swapParams
        );

        // If the proceeds should be converted to ETH, withdraw the ETH from the
        // WETH proceeds.
        if (_shouldConvertToETH) {
            weth.withdraw(proceeds);
        }

        // If necessary, refund ETH to the sender.
        if (refund > 0) {
            (bool success, ) = msg.sender.call{ value: refund }("");
            if (!success) {
                revert TransferFailed();
            }
        }

        return proceeds;
    }

    /// @dev Zaps the proceeds of closing a Hyperdrive position into a trader's
    ///      preferred tokens.
    /// @param _swapParams The Uniswap swap parameters for a multi-hop fill.
    /// @param _proceedsAsset The token received from Hyperdrive as proceeds.
    /// @param _shouldWrap A flag indicating whether or not the proceeds need to
    ///        be wrapped before the swap.
    /// @return proceeds The proceeds of the zap that were transferred to the
    ///         trader.
    function _zapOut(
        ISwapRouter.ExactInputParams memory _swapParams,
        address _proceedsAsset,
        bool _shouldWrap
    ) internal returns (uint256 proceeds) {
        // If necessary, wrap the Hyperdrive proceeds to prepare for the swap.
        address tokenIn = _swapParams.path.tokenIn();
        if (_shouldWrap) {
            // If the proceeds token is ETH, the proceeds should be converted to
            // WETH. We use the entire balance to avoid stuck ether.
            if (_proceedsAsset == ETH) {
                weth.deposit{ value: address(this).balance }();
            }
            // Otherwise, we wrap the entire token balance of the proceeds token
            // into the input token with the standard wrapping interface.
            else {
                // Approve and wrap the ERC20.
                //
                // NOTE: We increase the required approval amount by 1 wei so that the
                // router ends with an approval of 1 wei. This makes future approvals
                // cheaper by keeping the storage slot warm.
                uint256 balance_ = IERC20(_proceedsAsset).balanceOf(
                    address(this)
                );
                ERC20(_proceedsAsset).forceApprove(
                    address(tokenIn),
                    balance_ + 1
                );
                IWrappedERC20(tokenIn).wrap(balance_);
            }
        }

        // Update the swap parameters so that the input amount is equal to the
        // proceeds of closing the position and the minimum amount out is scaled
        // to the size of the proceeds. This will ensure that the swap is
        // properly sized for the proceeds that need to be converted.
        //
        // NOTE: Use the zap contract's balance rather than the proceeds
        // reported by Hyperdrive to avoid having to handle the difference
        // between rebasing and non-rebasing tokens.
        uint256 balance = IERC20(tokenIn).balanceOf(address(this));
        _swapParams.amountOutMinimum = balance.mulDivDown(
            _swapParams.amountOutMinimum,
            _swapParams.amountIn
        );
        _swapParams.amountIn = balance;

        // If the output token is WETH, we always unwrap to ETH. In this case,
        // we make this contract the recipient of the Uniswap swap.
        address tokenOut = _swapParams.path.tokenOut();
        address recipient = _swapParams.recipient;
        if (tokenOut == address(weth)) {
            _swapParams.recipient = address(this);
        }

        // Execute the Uniswap trade.
        //
        // NOTE: We increase the required approval amount by 1 wei so that the
        // router ends with an approval of 1 wei. This makes future approvals
        // cheaper by keeping the storage slot warm.
        ERC20(tokenIn).forceApprove(
            address(swapRouter),
            _swapParams.amountIn + 1
        );
        proceeds = swapRouter.exactInput(_swapParams);

        // If the output token is WETH, unwrap the WETH and send the ETH.
        if (tokenOut == address(weth)) {
            weth.withdraw(weth.balanceOf(address(this)));
            (bool success, ) = recipient.call{ value: address(this).balance }(
                ""
            );
            if (!success) {
                revert TransferFailed();
            }
        }

        return proceeds;
    }

    /// @dev Converts a quantity in base to vault shares. This works for all
    ///      Hyperdrive pools.
    /// @param _hyperdrive The Hyperdrive instance.
    /// @param _baseAmount The base amount.
    /// @return The converted vault shares amount.
    function _convertToShares(
        IHyperdrive _hyperdrive,
        uint256 _baseAmount
    ) internal view returns (uint256) {
        // If this is a mainnet deployment and the address is the legacy stETH
        // pool, we have to convert the proceeds to shares manually using Lido's
        // `getSharesByPooledEth` function.
        if (
            block.chainid == 1 &&
            address(_hyperdrive) == LEGACY_STETH_HYPERDRIVE
        ) {
            return
                ILido(_hyperdrive.vaultSharesToken()).getSharesByPooledEth(
                    _baseAmount
                );
        }
        // If this is a mainnet deployment and the address is the legacy stETH
        // pool, we have to convert the proceeds to shares manually using Lido's
        // `getSharesByPooledEth` function.
        else if (
            block.chainid == 1 && address(_hyperdrive) == LEGACY_SDAI_HYPERDRIVE
        ) {
            return
                IERC4626(_hyperdrive.vaultSharesToken()).convertToShares(
                    _baseAmount
                );
        }
        // Otherwise, we can use the built-in `convertToShares` function.
        else {
            return _hyperdrive.convertToShares(_baseAmount);
        }
    }
}
