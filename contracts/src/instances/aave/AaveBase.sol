// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IPool } from "aave/interfaces/IPool.sol";
import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { IAToken } from "../../interfaces/IAToken.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { HyperdriveBase } from "../../internal/HyperdriveBase.sol";
import { FixedPointMath } from "../../libraries/FixedPointMath.sol";
import { AaveConversions } from "./AaveConversions.sol";

/// @author DELV
/// @title AaveBase
/// @notice The base contract for the Aave Hyperdrive implementation.
/// @dev This Hyperdrive implementation is designed to work with standard
///      Aave vaults. Non-standard implementations may not work correctly
///      and should be carefully checked.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract AaveBase is HyperdriveBase {
    using FixedPointMath for uint256;
    using SafeERC20 for ERC20;

    /// @dev The Aave vault that is this instance's yield source.
    IPool internal immutable _vault;

    /// @notice Instantiates the AaveHyperdrive base contract.
    constructor() {
        // Initialize the Aave vault immutable.
        _vault = IAToken(address(_vaultSharesToken)).POOL();

        // Approve the Aave vault with 1 wei. This ensures that all of the
        // subsequent approvals will be writing to a dirty storage slot.
        ERC20(address(_baseToken)).forceApprove(address(_vault), 1);
    }

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

        // Deposit the base into the yield source.
        //
        // NOTE: We increase the required approval amount by 1 wei so that
        // the vault ends with an approval of 1 wei. This makes future
        // approvals cheaper by keeping the storage slot warm.
        ERC20(address(_baseToken)).forceApprove(
            address(_vault),
            _baseAmount + 1
        );
        _vault.supply(
            address(_baseToken), // asset
            _baseAmount, // amount
            address(this), // onBehalfOf
            // NOTE: Aave's referral program is inactive.
            0 // referralCode
        );

        return (_convertToShares(_baseAmount), 0);
    }

    /// @dev Process a deposit in vault shares.
    /// @param _shareAmount The vault shares amount to deposit.
    function _depositWithShares(
        uint256 _shareAmount,
        bytes calldata // unused _extraData
    ) internal override {
        // NOTE: We don't need to use `safeTransfer` since ATokens are
        // standard-compliant.
        //
        // Take custody of the deposit in vault shares.
        _vaultSharesToken.transferFrom(
            msg.sender,
            address(this),
            // NOTE: The AToken interface transfers in base, so we have to
            // convert the share amount to a base amount.
            _convertToBase(_shareAmount)
        );
    }

    /// @dev Process a withdrawal in base and send the proceeds to the
    ///      destination.
    /// @param _shareAmount The amount of vault shares to withdraw.
    /// @param _destination The destination of the withdrawal.
    /// @return amountWithdrawn The amount of base withdrawn.
    function _withdrawWithBase(
        uint256 _shareAmount,
        address _destination,
        bytes calldata // unused
    ) internal override returns (uint256 amountWithdrawn) {
        // Withdraw assets from the Aave vault to the destination.
        amountWithdrawn = _vault.withdraw(
            address(_baseToken), // asset
            // NOTE: Withdrawals are processed in base, so we have to convert
            // the share amount to a base amount.
            _convertToBase(_shareAmount), // amount
            _destination // onBehalfOf
        );

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
        // NOTE: We don't need to use `safeTransfer` since ATokens are
        // standard-compliant.
        //
        // Transfer vault shares to the destination.
        _vaultSharesToken.transfer(
            _destination,
            // NOTE: The AToken interface transfers in base, so we have to
            // convert the share amount to a base amount.
            _convertToBase(_shareAmount)
        );
    }

    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function _convertToBase(
        uint256 _shareAmount
    ) internal view override returns (uint256) {
        return AaveConversions.convertToBase(_baseToken, _vault, _shareAmount);
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function _convertToShares(
        uint256 _baseAmount
    ) internal view override returns (uint256) {
        return AaveConversions.convertToShares(_baseToken, _vault, _baseAmount);
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
