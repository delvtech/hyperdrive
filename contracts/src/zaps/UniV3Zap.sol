// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { ISwapRouter } from "../interfaces/ISwapRouter.sol";
import { IUniV3Zap } from "../interfaces/IUniV3Zap.sol";
import { AssetId } from "../libraries/AssetId.sol";

// FIXME: What events do we need?
//
/// @title UniV3Zap
/// @author DELV
/// @notice A zap contract that uses Uniswap v3 to execute swaps before or after
///         interacting with Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract UniV3Zap is IUniV3Zap {
    using SafeERC20 for ERC20;

    /// @notice The Uniswap swap router.
    ISwapRouter public immutable swapRouter;

    /// @notice Instantiates the zap contract.
    /// @param _swapRouter The uniswap swap router.
    constructor(ISwapRouter _swapRouter) {
        swapRouter = _swapRouter;
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
    /// @param _options The options that configure how the operation is settled.
    /// @param _isRebasing A flag indicating whether or not the vault shares
    ///        token is rebasing.
    /// @param _swapParams The Uniswap swap parameters for a single fill.
    /// @return lpShares The LP shares received by the LP.
    function addLiquidityZap(
        IHyperdrive _hyperdrive,
        uint256 _minLpSharePrice,
        uint256 _minApr,
        uint256 _maxApr,
        IHyperdrive.Options calldata _options,
        bool _isRebasing,
        ISwapRouter.ExactInputSingleParams calldata _swapParams
    ) external returns (uint256 lpShares) {
        // Validate the zap parameters.
        _validateZapIn(_hyperdrive, _options, _swapParams);

        // Zap the funds that will be used to add liquidity and approve the pool
        // to spend these funds.
        uint256 proceeds = _zapIn(_swapParams);
        // NOTE: We increase the required approval amount by 1 wei so that the
        // pool ends with an approval of 1 wei. This makes future approvals
        // cheaper by keeping the storage slot warm.
        ERC20(_swapParams.tokenIn).forceApprove(
            address(_hyperdrive),
            proceeds + 1
        );

        // Add liquidity using the proceeds of the trade. If the vault shares
        // token is a rebasing token, the proceeds amount needs to be converted
        // to vault shares.
        if (!_options.asBase && _isRebasing) {
            proceeds = _hyperdrive.convertToShares(proceeds);
        }
        lpShares = _hyperdrive.addLiquidity(
            proceeds,
            _minLpSharePrice,
            _minApr,
            _maxApr,
            _options
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
    /// @param _swapParams The Uniswap swap parameters for a single fill.
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
        ISwapRouter.ExactInputSingleParams calldata _swapParams
    ) external returns (uint256 proceeds, uint256 withdrawalShares) {
        // Validate the zap parameters.
        _validateZapOut(_hyperdrive, _options, _swapParams);

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
        proceeds = _zapOut(_swapParams);

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
    /// @param _swapParams The Uniswap swap parameters for a single fill.
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
        ISwapRouter.ExactInputSingleParams calldata _swapParams
    ) external returns (uint256 proceeds, uint256 withdrawalSharesRedeemed) {
        // Validate the zap parameters.
        _validateZapOut(_hyperdrive, _options, _swapParams);

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
        proceeds = _zapOut(_swapParams);

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
    /// @param _options The options that configure how the Hyperdrive trade is
    ///        settled.
    /// @param _isRebasing A flag indicating whether or not the vault shares
    ///        token is rebasing.
    /// @param _swapParams The Uniswap swap parameters for a single fill.
    /// @return maturityTime The maturity time of the bonds.
    /// @return longAmount The amount of bonds the trader received.
    function openLongZap(
        IHyperdrive _hyperdrive,
        uint256 _minOutput,
        uint256 _minVaultSharePrice,
        IHyperdrive.Options calldata _options,
        bool _isRebasing,
        ISwapRouter.ExactInputSingleParams calldata _swapParams
    ) external returns (uint256 maturityTime, uint256 longAmount) {
        // Validate the zap parameters.
        _validateZapIn(_hyperdrive, _options, _swapParams);

        // Zap the funds that will be used to open the long and approve the pool
        // to spend these funds.
        uint256 proceeds = _zapIn(_swapParams);
        // NOTE: We increase the required approval amount by 1 wei so that the
        // pool ends with an approval of 1 wei. This makes future approvals
        // cheaper by keeping the storage slot warm.
        ERC20(_swapParams.tokenIn).forceApprove(
            address(_hyperdrive),
            proceeds + 1
        );

        // Open a long using the proceeds of the trade. If the vault shares
        // token is a rebasing token, the proceeds amount needs to be converted
        // to vault shares.
        if (!_options.asBase && _isRebasing) {
            proceeds = _hyperdrive.convertToShares(proceeds);
        }
        (maturityTime, longAmount) = _hyperdrive.openLong(
            proceeds,
            _minOutput,
            _minVaultSharePrice,
            _options
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
    /// @param _swapParams The Uniswap swap parameters for a single fill.
    /// @return proceeds The proceeds of closing the long. These proceeds will
    ///         be in units determined by the Uniswap swap parameters.
    function closeLongZap(
        IHyperdrive _hyperdrive,
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        IHyperdrive.Options calldata _options,
        ISwapRouter.ExactInputSingleParams calldata _swapParams
    ) external returns (uint256 proceeds) {
        // Validate the zap parameters.
        _validateZapOut(_hyperdrive, _options, _swapParams);

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
        _zapOut(_swapParams);

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
    /// @param _options The options that configure how the Hyperdrive trade is
    ///        settled.
    /// @param _swapParams The Uniswap swap parameters for a single fill.
    /// @return maturityTime The maturity time of the bonds.
    /// @return deposit The amount the user deposited for this trade. The units
    ///         of this quantity are either base or vault shares, depending on
    ///         the value of `_options.asBase`.
    function openShortZap(
        IHyperdrive _hyperdrive,
        uint256 _bondAmount,
        uint256 _maxDeposit,
        uint256 _minVaultSharePrice,
        IHyperdrive.Options calldata _options,
        ISwapRouter.ExactInputSingleParams calldata _swapParams
    ) external returns (uint256 maturityTime, uint256 deposit) {
        // Validate the zap parameters.
        _validateZapIn(_hyperdrive, _options, _swapParams);

        // Zap the funds that will be used to open the long and approve the pool
        // to spend these funds.
        uint256 proceeds = _zapIn(_swapParams);
        // NOTE: We increase the required approval amount by 1 wei so that the
        // pool ends with an approval of 1 wei. This makes future approvals
        // cheaper by keeping the storage slot warm.
        ERC20(_swapParams.tokenIn).forceApprove(
            address(_hyperdrive),
            proceeds + 1
        );

        // Open a long using the proceeds of the trade.
        (maturityTime, deposit) = _hyperdrive.openShort(
            _bondAmount,
            _maxDeposit,
            _minVaultSharePrice,
            _options
        );

        // TODO: Is this the right UX? Ideally, we'd trade it back for them, but
        // that is more complicated and gas intensive.
        //
        // If there is capital left over after the rebase, send it back to the
        // trader.
        ERC20(_swapParams.tokenOut).safeTransfer(
            msg.sender,
            IERC20(_swapParams.tokenOut).balanceOf(address(this))
        );

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
    /// @param _swapParams The Uniswap swap parameters for a single fill.
    /// @return proceeds The proceeds of closing the short. These proceeds will
    ///         be in units determined by the Uniswap swap parameters.
    function closeShortZap(
        IHyperdrive _hyperdrive,
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        IHyperdrive.Options calldata _options,
        ISwapRouter.ExactInputSingleParams calldata _swapParams
    ) external returns (uint256 proceeds) {
        // Validate the zap parameters.
        _validateZapOut(_hyperdrive, _options, _swapParams);

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
        _zapOut(_swapParams);

        return proceeds;
    }

    /// Helpers ///

    /// @dev Validate the swap parameters for zapping tokens into Hyperdrive.
    /// @param _hyperdrive The Hyperdrive pool to open the long on.
    /// @param _options The options that configure how the operation is settled.
    /// @param _swapParams The Uniswap swap parameters for a single fill.
    function _validateZapIn(
        IHyperdrive _hyperdrive,
        IHyperdrive.Options calldata _options,
        ISwapRouter.ExactInputSingleParams memory _swapParams
    ) internal view {
        // Ensure that the swap recipient is this contract.
        if (_swapParams.recipient != address(this)) {
            revert InvalidRecipient();
        }

        // Ensure that if we're opening the long with base that the output token
        // of the zap is the Hyperdrive pool's base token.
        if (
            _options.asBase && _swapParams.tokenOut != _hyperdrive.baseToken()
        ) {
            revert InvalidOutputToken();
        }
        // Ensure that if we're opening the long with vault shares that the
        // output token of the zap is the Hyperdrive pool's vault shares token.
        else if (
            !_options.asBase &&
            _swapParams.tokenOut != _hyperdrive.vaultSharesToken()
        ) {
            revert InvalidOutputToken();
        }
    }

    /// @dev Validate the swap parameters for zapping tokens out of Hyperdrive.
    /// @param _hyperdrive The Hyperdrive pool to open the long on.
    /// @param _options The options that configure how the operation is settled.
    /// @param _swapParams The Uniswap swap parameters for a single fill.
    function _validateZapOut(
        IHyperdrive _hyperdrive,
        IHyperdrive.Options calldata _options,
        ISwapRouter.ExactInputSingleParams memory _swapParams
    ) internal view {
        // Ensure that the swap recipient is the sender.
        if (_swapParams.recipient != msg.sender) {
            revert InvalidRecipient();
        }

        // Ensure that if we're opening the long with base that the output token
        // of the zap is the Hyperdrive pool's base token.
        if (_options.asBase && _swapParams.tokenIn != _hyperdrive.baseToken()) {
            revert InvalidOutputToken();
        }
        // Ensure that if we're opening the long with vault shares that the
        // output token of the zap is the Hyperdrive pool's vault shares token.
        else if (
            !_options.asBase &&
            _swapParams.tokenIn != _hyperdrive.vaultSharesToken()
        ) {
            revert InvalidOutputToken();
        }
    }

    /// @dev Zaps funds into this contract to open positions on Hyperdrive.
    /// @param _swapParams The Uniswap swap parameters for a single fill.
    /// @return proceeds The amount of assets that were zapped into this
    ///         contract.
    function _zapIn(
        ISwapRouter.ExactInputSingleParams memory _swapParams
    ) internal returns (uint256 proceeds) {
        // Take custody of the assets to swap. Then we update the swap
        // parameters so that the swap's input amount is equal to this
        // contract's total balance of the input token. This ensures that stuck
        // tokens from this contract are used.
        ERC20(_swapParams.tokenIn).safeTransferFrom(
            msg.sender,
            address(this),
            _swapParams.amountIn
        );
        _swapParams.amountIn = IERC20(_swapParams.tokenIn).balanceOf(
            address(this)
        );

        // Execute the Uniswap trade.
        //
        // NOTE: We increase the required approval amount by 1 wei so that the
        // router ends with an approval of 1 wei. This makes future approvals
        // cheaper by keeping the storage slot warm.
        ERC20(_swapParams.tokenIn).forceApprove(
            address(swapRouter),
            proceeds + 1
        );
        proceeds = swapRouter.exactInputSingle(_swapParams);

        return proceeds;
    }

    /// @dev Zaps the proceeds of closing a Hyperdrive position into a trader's
    ///      preferred tokens.
    /// @param _swapParams The Uniswap swap parameters for a single fill.
    /// @return proceeds The proceeds of the zap that were transferred to the
    ///         trader.
    function _zapOut(
        ISwapRouter.ExactInputSingleParams memory _swapParams
    ) internal returns (uint256 proceeds) {
        // Update the swap parameters so that the swap's input amount is equal
        // to this contract's total balance of the input token. This ensures
        // that stuck tokens from this contract are used.
        _swapParams.amountIn = IERC20(_swapParams.tokenIn).balanceOf(
            address(this)
        );

        // Execute the Uniswap trade.
        //
        // NOTE: We increase the required approval amount by 1 wei so that the
        // router ends with an approval of 1 wei. This makes future approvals
        // cheaper by keeping the storage slot warm.
        ERC20(_swapParams.tokenIn).forceApprove(
            address(swapRouter),
            proceeds + 1
        );
        proceeds = swapRouter.exactInputSingle(_swapParams);

        return proceeds;
    }
}
