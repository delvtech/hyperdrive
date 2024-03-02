// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { ILido } from "../../interfaces/ILido.sol";
import { HyperdriveBase } from "../../internal/HyperdriveBase.sol";
import { FixedPointMath, ONE } from "../../libraries/FixedPointMath.sol";

/// @author DELV
/// @title StethHyperdrive
/// @notice The base contract for the stETH Hyperdrive implementation.
/// @dev Lido has it's own notion of shares to account for the accrual of
///      interest on the ether pooled in the Lido protocol. Instead of
///      maintaining a balance of shares, this integration can simply use Lido
///      shares directly.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract StETHBase is HyperdriveBase {
    using FixedPointMath for uint256;

    /// @dev The Lido contract.
    ILido internal immutable _lido;

    /// @notice Instantiates the stETH Hyperdrive base contract.
    /// @param __lido The Lido contract.
    constructor(ILido __lido) {
        _lido = __lido;
    }

    /// Yield Source ///

    /// @dev Accepts a transfer from the user in base or the yield source token.
    /// @param _amount The amount of capital to deposit. The units of this
    ///        quantity are either base or vault shares, depending on the value
    ///        of `_options.asBase`.
    /// @param _options The options that configure how the trade is settled. The
    ///        only option used in this deposit implementation is
    ///        `_options.asBase` which determines if the deposit is settled in
    ///        ETH or stETH shares.
    /// @return shares The amount of capital deposited measured in vault shares.
    /// @return vaultSharePrice The current vault share price.
    function _deposit(
        uint256 _amount,
        IHyperdrive.Options calldata _options
    ) internal override returns (uint256 shares, uint256 vaultSharePrice) {
        uint256 refund;
        if (_options.asBase) {
            // Ensure that sufficient ether was provided.
            if (msg.value < _amount) {
                revert IHyperdrive.TransferFailed();
            }

            // If the user sent more ether than the amount specified, refund the
            // excess ether.
            refund = msg.value - _amount;

            // Submit the provided ether to Lido to be deposited. The fee
            // collector address is passed as the referral address; however,
            // users can specify whatever referrer they'd like by depositing
            // stETH instead of ETH.
            shares = _lido.submit{ value: _amount }(_feeCollector);
        } else {
            // Refund any ether that was sent to the contract.
            refund = msg.value;

            // Transfer stETH shares into the contract.
            shares = _amount;
            _lido.transferSharesFrom(msg.sender, address(this), shares);
        }

        // Calculate the vault share price.
        vaultSharePrice = _pricePerVaultShare();

        // Return excess ether that was sent to the contract.
        if (refund > 0) {
            (bool success, ) = payable(msg.sender).call{ value: refund }("");
            if (!success) {
                revert IHyperdrive.TransferFailed();
            }
        }

        return (shares, vaultSharePrice);
    }

    /// @notice Processes a trader's withdrawal. This yield source only supports
    ///         withdrawals in stETH shares.
    /// @param _shares The amount of vault shares to withdraw from Hyperdrive.
    /// @param _vaultSharePrice The vault share price.
    /// @param _options The options that configure the withdrawal. The options
    ///        used in this withdrawal implementation are `_options.destination`,
    ///        which specifies the recipient of the withdrawal, and
    ///        `_options.asBase`, which determines if the withdrawal is settled
    ///        in ETH or stETH. The `_options.asBase` option must be false since
    ///        stETH withdrawals aren't processed instantaneously. Users that
    ///        want to withdraw can manage their withdrawal separately.
    /// @return The proceeds of the withdrawal. The units of this quantity are
    ///         vault shares since this yield source doesn't support withdrawals
    ///         in base.
    function _withdraw(
        uint256 _shares,
        uint256 _vaultSharePrice,
        IHyperdrive.Options calldata _options
    ) internal override returns (uint256) {
        // stETH withdrawals aren't necessarily instantaneous. Users that want
        // to withdraw can manage their withdrawal separately.
        if (_options.asBase) {
            revert IHyperdrive.UnsupportedToken();
        }

        // NOTE: Round down to underestimate the base proceeds.
        //
        // Correct for any error that crept into the calculation of the share
        // amount by converting the shares to base and then back to shares
        // using the vault's share conversion logic.
        uint256 baseAmount = _shares.mulDown(_vaultSharePrice);
        _shares = _lido.getSharesByPooledEth(baseAmount);

        // If we're withdrawing zero shares, short circuit and return 0.
        if (_shares == 0) {
            return 0;
        }

        // Transfer the stETH shares to the destination.
        _lido.transferShares(_options.destination, _shares);

        return _shares;
    }

    /// @dev Returns the current vault share price. We simply use Lido's
    ///      internal share price.
    /// @return price The current vault share price.
    function _pricePerVaultShare()
        internal
        view
        override
        returns (uint256 price)
    {
        return _lido.getPooledEthByShares(ONE);
    }

    /// @dev We override the message value check since this integration is
    ///      payable.
    function _checkMessageValue() internal pure override {}
}
