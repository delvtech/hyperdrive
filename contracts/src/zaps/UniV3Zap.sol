// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { ISwapRouter } from "../interfaces/ISwapRouter.sol";
import { AssetId } from "../libraries/AssetId.sol";

// FIXME: I don't love this name. Can we do better?
//
// FIXME: Add an interface.
//
// FIXME: What events do we need?
//
// FIXME: Once all of the functions are implemented, go through and try to DRY
//        everything up.
//
/// @title UniV3Zap
/// @author DELV
/// @notice A zap contract that uses Uniswap v3 to execute swaps before or after
///         interacting with Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract UniV3Zap {
    using SafeERC20 for ERC20;

    /// @notice Thrown when attempting to zap to an invalid input token.
    error InvalidInputToken();

    /// @notice Thrown when attempting to zap to an invalid output token.
    error InvalidOutputToken();

    /// @notice Thrown when attempting to zap to an invalid recipient.
    error InvalidRecipient();

    // FIXME: Is it okay to have this as an immutable, or should we pass this as
    // an argument?
    //
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
    // FIXME: Is there a reason to not use the multi-hop parameters?
    // FIXME: Is there a better way to handle execution that is more generic?
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
        // FIXME: Can we DRY up these checks?
        //
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

    // FIXME: Remove liquidity

    // FIXME: Redeem withdrawal shares

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
    // FIXME: Is there a reason to not use the multi-hop parameters?
    // FIXME: Is there a better way to handle execution that is more generic?
    /// @param _swapParams The Uniswap swap parameters for a single fill.
    /// @return maturityTime The maturity time of the bonds.
    /// @return longAmount The amount of bonds the user received.
    function openLongZap(
        IHyperdrive _hyperdrive,
        uint256 _minOutput,
        uint256 _minVaultSharePrice,
        IHyperdrive.Options calldata _options,
        bool _isRebasing,
        ISwapRouter.ExactInputSingleParams calldata _swapParams
    ) external returns (uint256 maturityTime, uint256 longAmount) {
        // FIXME: Can we DRY up these checks?
        //
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
    // FIXME: Is there a reason to not use the multi-hop parameters?
    // FIXME: Is there a better way to handle execution that is more generic?
    /// @param _swapParams The Uniswap swap parameters for a single fill.
    /// @return proceeds The proceeds sent to the user.
    function closeLongZap(
        IHyperdrive _hyperdrive,
        uint256 _maturityTime,
        uint256 _bondAmount,
        uint256 _minOutput,
        IHyperdrive.Options calldata _options,
        ISwapRouter.ExactInputSingleParams calldata _swapParams
    ) external returns (uint256 proceeds) {
        // FIXME: Can we DRY up these checks?
        //
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

        // Take custody of the long position.
        _hyperdrive.transferFrom(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, _maturityTime),
            msg.sender,
            address(this),
            _bondAmount
        );

        // Close the long, zap the proceeds into the target asset, and send
        // them to the user.
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

    // FIXME
    //
    // FIXME: Handle refunds for shorts.

    /// Helpers ///

    /// @notice Zaps funds into this contract to open positions on Hyperdrive.
    // FIXME: Is there a reason to not use the multi-hop parameters?
    // FIXME: Is there a better way to handle execution that is more generic?
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

    /// @notice Zaps the proceeds of closing a Hyperdrive position into a users
    ///         preferred tokens.
    // FIXME: Is there a reason to not use the multi-hop parameters?
    // FIXME: Is there a better way to handle execution that is more generic?
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
