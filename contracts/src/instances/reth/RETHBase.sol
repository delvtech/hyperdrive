// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { HyperdriveBase } from "../../internal/HyperdriveBase.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IRocketTokenRETH } from "../../interfaces/IRocketTokenRETH.sol";

/// @author DELV
/// @title RETHHyperdrive
/// @notice The base contract for the rETH Hyperdrive implementation.
/// @dev Rocket Pool has it's own notion of shares to account for the accrual of
///      interest on the ether pooled in the Rocket Pool protocol. Instead of
///      maintaining a balance of shares, this integration can simply use Rocket Pool
///      shares directly.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract RETHBase is HyperdriveBase {
    using SafeERC20 for ERC20;

    /// Yield Source ///

    function _depositWithBase(
        uint256, // unused
        bytes calldata // unused
    ) internal pure override returns (uint256, uint256) {
        // Deposits with ETH is not supported because of accounting
        // issues due to the Rocket Pool deposit fee.
        revert IHyperdrive.UnsupportedToken();
    }

    /// @dev Process a deposit in vault shares.
    /// @param _shareAmount The vault shares amount to deposit.
    function _depositWithShares(
        uint256 _shareAmount,
        bytes calldata // unused
    ) internal override {
        // Transfer rETH shares into the contract.
        ERC20(address(_vaultSharesToken)).safeTransferFrom(
            msg.sender,
            address(this),
            _shareAmount
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
        // Burning rETH shares in exchange for ether.
        // Ether proceeds are credited to this contract.
        IRocketTokenRETH(address(_vaultSharesToken)).burn(_shareAmount);

        // Amount of ETH that was withdrawn from the yield source and
        // will be sent to the destination address.
        amountWithdrawn = address(this).balance;

        // Return withdrawn ether to the destination.
        (bool success, ) = payable(_destination).call{ value: amountWithdrawn }(
            ""
        );
        if (!success) {
            revert IHyperdrive.TransferFailed();
        }
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
        // Transfer the rETH shares to the destination.
        ERC20(address(_vaultSharesToken)).safeTransfer(
            _destination,
            _shareAmount
        );
    }

    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _shareAmount The vault shares amount.
    /// @return baseAmount The base amount.
    function _convertToBase(
        uint256 _shareAmount
    ) internal view override returns (uint256) {
        return
            IRocketTokenRETH(address(_vaultSharesToken)).getEthValue(
                _shareAmount
            );
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _baseAmount The base amount.
    /// @return shareAmount The vault shares amount.
    function _convertToShares(
        uint256 _baseAmount
    ) internal view override returns (uint256) {
        return
            IRocketTokenRETH(address(_vaultSharesToken)).getRethValue(
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

    /// @dev Allows ether to be received only from the Rocket Pool rETH
    ///      token contract. Supports withdrawing as ethers from this
    ///      yield source.
    receive() external payable {
        if (msg.sender != address(_vaultSharesToken)) {
            revert IHyperdrive.TransferFailed();
        }
    }
}
