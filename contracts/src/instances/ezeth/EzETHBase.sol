// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IRestakeManager, IRenzoOracle } from "../../interfaces/IRenzo.sol";
import { HyperdriveBase } from "../../internal/HyperdriveBase.sol";
import { EzETHConversions } from "./EzETHConversions.sol";

/// @author DELV
/// @title ezETH Base Contract
/// @notice The base contract for the ezETH Hyperdrive implementation.
/// @dev ezETH shares are held separately in the ezETH token contract.  The
///      value of those tokens w.r.t. ETH are found by calling the
///      RestakeManager's calculateTVL for the total pooled ETH value and
///      dividing by the totalSupply of ezETH.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract EzETHBase is HyperdriveBase {
    /// @dev The Renzo entrypoint contract.
    IRestakeManager internal immutable _restakeManager;

    /// @dev The RenzoOracle contract.
    IRenzoOracle internal immutable _renzoOracle;

    /// @notice Instantiates the ezETH Hyperdrive base contract.
    /// @param __restakeManager The Renzo Restakemanager contract.
    constructor(IRestakeManager __restakeManager) {
        _restakeManager = __restakeManager;
        _renzoOracle = IRenzoOracle(__restakeManager.renzoOracle());
    }

    /// Yield Source ///

    //// @dev This option isn't supported because the minting calculation is too
    ///       imprecise.
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
        bytes calldata // unused
    ) internal override {
        // NOTE: We don't need to use `safeTransfer` since ezETH uses
        // OpenZeppelin's ERC20Upgradeable implementation and is
        // standard-compliant.
        //
        // Transfer ezETH shares into the contract.
        _vaultSharesToken.transferFrom(msg.sender, address(this), _shareAmount);
    }

    /// @dev Process a withdrawal in base and send the proceeds to the
    ///      destination.
    function _withdrawWithBase(
        uint256, // unused
        address, // unused
        bytes calldata // unused
    ) internal pure override returns (uint256) {
        // ezETH withdrawals aren't necessarily instantaneous. Users that want
        // to withdraw can manage their withdrawal separately.
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
        // NOTE: We don't need to use `safeTransfer` since ezETH uses
        // OpenZeppelin's ERC20Upgradeable implementation and is
        // standard-compliant.
        //
        // Transfer the ezETH shares to the destination.
        _vaultSharesToken.transfer(_destination, _shareAmount);
    }

    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _shareAmount The vault shares amount.
    /// @return baseAmount The base amount.
    function _convertToBase(
        uint256 _shareAmount
    ) internal view override returns (uint256) {
        return
            EzETHConversions.convertToBase(
                _renzoOracle,
                _restakeManager,
                _vaultSharesToken,
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
            EzETHConversions.convertToShares(
                _renzoOracle,
                _restakeManager,
                _vaultSharesToken,
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
