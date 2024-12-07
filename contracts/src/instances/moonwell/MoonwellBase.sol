// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

// FIXME
import { console2 as console } from "forge-std/console2.sol";

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "../../interfaces/IERC4626.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { HyperdriveBase } from "../../internal/HyperdriveBase.sol";
import { IMToken } from "../../interfaces/IMoonwell.sol";
import { MoonwellConversions } from "./MoonwellConversions.sol";

/// @author DELV
/// @title MoonwellBase
/// @notice The base contract for the Moonwell Hyperdrive implementation.
/// @dev This Hyperdrive implementation is designed to work with standard
///      Moonwell vaults. Non-standard implementations may not work correctly
///      and should be carefully checked.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract MoonwellBase is HyperdriveBase {
    using SafeERC20 for ERC20;

    /// Yield Source ///

    /// @dev Accepts a deposit from the user in base.
    /// @return The shares that were minted in the deposit.
    /// @return The amount of ETH to refund. Since this yield source isn't
    ///         payable, this is always zero.
    function _depositWithBase(
        uint256 _baseAmount,
        bytes calldata // unused
    ) internal override returns (uint256, uint256) {
        // Take custody of the deposit in base.
        ERC20(address(_baseToken)).safeTransferFrom(
            msg.sender,
            address(this),
            _baseAmount
        );

        // Deposit the base into the yield source.
        //
        // NOTE: We increase the required approval amount by 1 wei so that
        // the vault ends with an approval of 1 wei. This makes future
        // approvals cheaper by keeping the storage slot warm.
        ERC20(address(_baseToken)).forceApprove(
            address(_vaultSharesToken),
            _baseAmount + 1
        );

        // IMToken(address(_vaultSharesToken)).accrueInterest();
        IMToken token = IMToken(address(_vaultSharesToken));

        // console.log("sharesBefore: ", _convertToShares(_baseAmount));
        // console.log("exchangeRateStored before:  ", token.exchangeRateStored());
        // console.log("exchangeRateCurrent before: ", MoonwellConversions.exchangeRateCurrent(IMToken(address(_vaultSharesToken))));

        uint256 sharesMinted = _convertToShares(_baseAmount);
        // console.log("baseAmount:           ", _baseAmount);
        // console.log("cash before mint:     ", token.getCash());
        // console.log("borrows before mint:  ", token.totalBorrows());
        // console.log("reserves before mint: ", token.totalReserves());
        // console.log("b Index before mint:  ", token.borrowIndex());
        // console.log("supply before mint:   ", token.totalSupply());

        uint err = IMToken(address(_vaultSharesToken)).mint(_baseAmount);

        // console.log("cash after mint:      ", token.getCash());
        // console.log("borrows after mint:   ", token.totalBorrows());
        // console.log("reserves after mint:  ", token.totalReserves());
        // console.log("b Index after mint:   ", token.borrowIndex());
        // console.log("supply after mint:    ", token.totalSupply());

        // console.log("exchangeRateStored after:  ", token.exchangeRateStored());
        // console.log("exchangeRateCurrent after: ", MoonwellConversions.exchangeRateCurrent(IMToken(address(_vaultSharesToken))));

        // console.log("base converted to shares after minting:  ", _convertToShares(_baseAmount));
        // console.log("base converted to shares before minting: ", sharesMinted);

        return (sharesMinted, 0);
    }

    /// @dev Process a deposit in vault shares.
    /// @param _shareAmount The vault shares amount to deposit.
    function _depositWithShares(
        uint256 _shareAmount,
        bytes calldata // unused
    ) internal override {
        // Take custody of the deposit in vault shares.
        ERC20(address(_vaultSharesToken)).safeTransferFrom(
            msg.sender,
            address(this),
            _shareAmount
        );
    }

    /// @dev Process a withdrawal in base and send the proceeds to the
    ///      destination.
    /// @param _destination The destination of the withdrawal.
    /// @return amountWithdrawn The amount of base withdrawn.
    function _withdrawWithBase(
        uint256 _shareAmount,
        address _destination,
        bytes calldata // unused
    ) internal override returns (uint256 amountWithdrawn) {
        // Redeem assets from the yield source and ensure that the redemption
        // succeeded.
        uint256 balanceBefore = _baseToken.balanceOf(address(this));
        uint256 status = IMToken(address(_vaultSharesToken)).redeem(
            _shareAmount
        );
        if (status != 0) {
            revert IHyperdrive.TransferFailed();
        }

        // Transfer the assets that were withdrawn to the destination.
        amountWithdrawn = _baseToken.balanceOf(address(this)) - balanceBefore;
        ERC20(address(_baseToken)).safeTransfer(_destination, amountWithdrawn);

        return amountWithdrawn;
    }

    /// @dev Process a withdrawal in vault shares and send the proceeds to the
    ///      destination.
    /// @param _shareAmount The amount of vault shares to withdraw.
    /// @param _destination The destination of the withdrawal.
    function _withdrawWithShares(
        uint256 _shareAmount,
        address _destination,
        bytes calldata // unused
    ) internal override {
        // Transfer vault shares to the destination.
        ERC20(address(_vaultSharesToken)).safeTransfer(
            _destination,
            _shareAmount
        );
    }

    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function _convertToBase(
        uint256 _shareAmount
    ) internal view override returns (uint256) {
        return
            MoonwellConversions.convertToBase(
                IMToken(address(_vaultSharesToken)),
                _shareAmount
            );
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function _convertToShares(
        uint256 _baseAmount
    ) internal view override returns (uint256) {
        return
            MoonwellConversions.convertToShares(
                IMToken(address(_vaultSharesToken)),
                _baseAmount
            );
    }

    /// @dev Gets the total amount of shares held by the pool in the yield
    ///      source.
    /// @return shareAmount The total amount of shares.
    function _totalShares()
        internal
        view
        override
        returns (uint256 shareAmount)
    {
        return _vaultSharesToken.balanceOf(address(this));
    }

    /// @dev We override the message value check since this integration is
    ///      not payable.
    function _checkMessageValue() internal view override {
        if (msg.value != 0) {
            revert IHyperdrive.NotPayable();
        }
    }
}
