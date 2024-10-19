// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { HyperdriveBase } from "../../internal/HyperdriveBase.sol";
import { AerodromeLpConversions } from "./AerodromeLpConversions.sol";

/// @author DELV
/// @title AerodromeLpBase
/// @notice The base contract for the AerodromeLp Hyperdrive implementation.
/// @dev This Hyperdrive implementation is designed to work with standard
///      AerodromeLp vaults. Non-standard implementations may not work correctly
///      and should be carefully checked.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract AerodromeLpBase is HyperdriveBase {
    using SafeERC20 for ERC20;

    /// Yield Source ///

    /// @dev Accepts a deposit from the user in base.
    /// @param _baseAmount The base amount to deposit.
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

        // There is no vault to deposit into, so we just return the base amount.
        return (_baseAmount, 0);
    }

    /// @dev There is no vault, so we can't deposit with shares.
    function _depositWithShares(
        uint256, // unused _shareAmount,
        bytes calldata // unused _extraData
    ) internal pure override {
        revert IHyperdrive.UnsupportedToken();
    }

    /// @dev Process a withdrawal in base and send the proceeds to the
    ///      destination.
    /// @param _shareAmount There is no vault, so this it the base token amount
    ///                     to withdraw.
    /// @param _destination The destination of the withdrawal.
    /// @return amountWithdrawn The amount of base withdrawn.
    function _withdrawWithBase(
        uint256 _shareAmount,
        address _destination,
        bytes calldata // unused
    ) internal override returns (uint256 amountWithdrawn) {
        // resulting base to the destination address.
        ERC20(address(_baseToken)).safeTransfer(_destination, _shareAmount);

        return _shareAmount;
    }

    /// @dev Withdrawals with shares are not supported for this integration.
    function _withdrawWithShares(
        uint256, // unused _shareAmount
        address, // unused _destination
        bytes calldata // unused
    ) internal pure override {
        revert IHyperdrive.UnsupportedToken();
    }

    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function _convertToBase(
        uint256 _shareAmount
    ) internal pure override returns (uint256) {
        return AerodromeLpConversions.convertToBase(_shareAmount);
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function _convertToShares(
        uint256 _baseAmount
    ) internal pure override returns (uint256) {
        return AerodromeLpConversions.convertToShares(_baseAmount);
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
        return _baseToken.balanceOf(address(this));
    }

    /// @dev We override the message value check since this integration is
    ///      not payable.
    function _checkMessageValue() internal view override {
        if (msg.value != 0) {
            revert IHyperdrive.NotPayable();
        }
    }
}
