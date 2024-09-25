// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { ISwapRouter } from "../interfaces/ISwapRouter.sol";

// FIXME: I don't love this name. Can we do better?
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

    // FIXME: Is it cool to have this as an immutable, or should we pass this as
    // an argument.
    //
    /// @notice The Uniswap swap router.
    ISwapRouter public immutable swapRouter;

    /// @notice Instantiates the zap contract.
    /// @param _swapRouter The uniswap swap router.
    constructor(ISwapRouter _swapRouter) {
        swapRouter = _swapRouter;
    }

    /// LPs ///

    // FIXME

    /// Longs ///

    /// @notice Executes a swap on Uniswap and uses the proceeds to open a long
    ///         on Hyperdrive.
    /// @param _hyperdrive The Hyperdrive pool to open the long on.
    // FIXME: Is there a reason to not use the multi-hop parameters?
    // FIXME: Is there a better way to handle execution that is more generic?
    /// @param _swapParams The Uniswap swap parameters for a single fill.
    /// @param _minOutput The minimum number of bonds to receive.
    /// @param _minVaultSharePrice The minimum vault share price at which to
    ///        open the long. This allows traders to protect themselves from
    ///        opening a long in a checkpoint where negative interest has
    ///        accrued.
    /// @param _options The options that configure how the Hyperdrive trade is
    ///        settled.
    /// @return maturityTime The maturity time of the bonds.
    /// @return longAmount The amount of bonds the user received.
    function openLongZap(
        IHyperdrive _hyperdrive,
        ISwapRouter.ExactInputSingleParams calldata _swapParams,
        uint256 _minOutput,
        uint256 _minVaultSharePrice,
        IHyperdrive.Options calldata _options
    ) external returns (uint256 maturityTime, uint256 longAmount) {
        // Zap the funds that will be used to open the long.
        uint256 proceeds = _zapIn(_swapParams);

        // Open a long using the proceeds of the trade.
        //
        // NOTE: We increase the required approval amount by 1 wei so that
        // the vault ends with an approval of 1 wei. This makes future
        // approvals cheaper by keeping the storage slot warm.
        ERC20(_swapParams.tokenIn).forceApprove(
            address(_hyperdrive),
            proceeds + 1
        );
        (maturityTime, longAmount) = _hyperdrive.openLong(
            proceeds,
            _minOutput,
            _minVaultSharePrice,
            _options
        );

        return (maturityTime, longAmount);
    }

    /// Shorts ///

    // FIXME

    /// Helpers ///

    /// @notice Zaps funds into this contract to open positions on Hyperdrive.
    /// @param _swapParams The Uniswap swap parameters for a single fill.
    /// @return proceeds The amount of assets that were zapped into this
    ///         contract.
    function _zapIn(
        ISwapRouter.ExactInputSingleParams calldata _swapParams
    ) internal returns (uint256 proceeds) {
        // Take custody of the assets to swap.
        ERC20(_swapParams.tokenIn).safeTransferFrom(
            msg.sender,
            address(this),
            _swapParams.amountIn
        );

        // FIXME: Ensure that the recipient is this contract.
        //
        // Execute the Uniswap trade.
        proceeds = swapRouter.exactInputSingle(_swapParams);

        return proceeds;
    }
}
