// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { ICornSilo } from "../../interfaces/ICornSilo.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { HyperdriveBase } from "../../internal/HyperdriveBase.sol";
import { CornConversions } from "./CornConversions.sol";

/// @author DELV
/// @title CornBase
/// @notice The base contract for the Corn Hyperdrive implementation.
/// @dev This Hyperdrive implementation is designed to work with standard
///      Corn vaults. Non-standard implementations may not work correctly
///      and should be carefully checked.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract CornBase is HyperdriveBase {
    using SafeERC20 for ERC20;

    /// @dev The Corn Silo contract. This is where the base token will be
    ///      deposited.
    ICornSilo internal immutable _cornSilo;

    /// @notice Instantiates the CornHyperdrive base contract.
    /// @param __cornSilo The Corn Silo contract.
    constructor(ICornSilo __cornSilo) {
        _cornSilo = __cornSilo;
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
            address(_cornSilo),
            _baseAmount + 1
        );
        uint256 sharesMinted = _cornSilo.deposit(
            address(_baseToken),
            _baseAmount
        );

        return (sharesMinted, 0);
    }

    /// @dev Deposits with shares are not supported for this integration.
    function _depositWithShares(
        uint256, // unused _shareAmount
        bytes calldata // unused _extraData
    ) internal pure override {
        revert IHyperdrive.UnsupportedToken();
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
        // Redeem the Corn shares and send the resulting base tokens to the
        // destination.
        amountWithdrawn = _cornSilo.redeemToken(
            address(_baseToken),
            _shareAmount
        );
        ERC20(address(_baseToken)).safeTransfer(_destination, amountWithdrawn);

        return amountWithdrawn;
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
        return CornConversions.convertToBase(_shareAmount);
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function _convertToShares(
        uint256 _baseAmount
    ) internal pure override returns (uint256) {
        return CornConversions.convertToShares(_baseAmount);
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
        return _cornSilo.sharesOf(address(this), address(_baseToken));
    }

    /// @dev We override the message value check since this integration is
    ///      not payable.
    function _checkMessageValue() internal view override {
        if (msg.value != 0) {
            revert IHyperdrive.NotPayable();
        }
    }
}
