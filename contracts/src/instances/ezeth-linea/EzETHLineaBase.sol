// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IXRenzoDeposit } from "../../interfaces/IXRenzoDeposit.sol";
import { HyperdriveBase } from "../../internal/HyperdriveBase.sol";
import { EzETHLineaConversions } from "./EzETHLineaConversions.sol";

/// @author DELV
/// @title EzETHLineaBase
/// @notice The base contract for the EzETH integration on Linea.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract EzETHLineaBase is HyperdriveBase {
    /// @dev The Renzo deposit contract on Linea. The latest mint rate is used
    ///      as the vault share price.
    IXRenzoDeposit internal immutable _xRenzoDeposit;

    /// @notice Instantiates the ezETH Linea Hyperdrive base contract.
    /// @param __xRenzoDeposit The xRenzoDeposit contract that provides the
    ///        vault share price.
    constructor(IXRenzoDeposit __xRenzoDeposit) {
        _xRenzoDeposit = __xRenzoDeposit;
    }

    /// Yield Source ///

    /// @dev Deposits with base are not supported for this integration.
    ///      xRenzoDeposit takes a bridge fee which causes problems with the
    ///      `openShort` accounting.
    function _depositWithBase(
        uint256, // unused
        bytes calldata // unused
    ) internal pure override returns (uint256, uint256) {
        revert IHyperdrive.UnsupportedToken();
    }

    /// @dev Process a deposit in vault shares.
    /// @param _shareAmount The vault shares amount to deposit.
    function _depositWithShares(
        uint256 _shareAmount,
        bytes calldata // unused _extraData
    ) internal override {
        // NOTE: Since Linea ezETH is a xERC20, which is itself an OpenZeppelin
        // ERC20 token, we don't need to use `safeTransferFrom`.
        //
        // Take custody of the deposit in vault shares.
        bool success = _vaultSharesToken.transferFrom(
            msg.sender,
            address(this),
            _shareAmount
        );
        if (!success) {
            revert IHyperdrive.TransferFailed();
        }
    }

    /// @dev Withdrawals with base are not supported for this integration.
    function _withdrawWithBase(
        uint256, // unused
        address, // unused
        bytes calldata // unused
    ) internal pure override returns (uint256) {
        revert IHyperdrive.UnsupportedToken();
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
        // NOTE: Since Linea ezETH is a xERC20, which is itself an OpenZeppelin
        // ERC20 token, we don't need to use `safeTransfer`.
        //
        // Transfer vault shares to the destination.
        bool success = _vaultSharesToken.transfer(_destination, _shareAmount);
        if (!success) {
            revert IHyperdrive.TransferFailed();
        }
    }

    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function _convertToBase(
        uint256 _shareAmount
    ) internal view override returns (uint256) {
        return
            EzETHLineaConversions.convertToBase(_xRenzoDeposit, _shareAmount);
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function _convertToShares(
        uint256 _baseAmount
    ) internal view override returns (uint256) {
        return
            EzETHLineaConversions.convertToShares(_xRenzoDeposit, _baseAmount);
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
