// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IRocketStorage } from "../../interfaces/IRocketStorage.sol";
import { IRocketDepositPool } from "../../interfaces/IRocketDepositPool.sol";
import { IRocketTokenRETH } from "../../interfaces/IRocketTokenRETH.sol";
import { HyperdriveBase } from "../../internal/HyperdriveBase.sol";
import { FixedPointMath, ONE } from "../../libraries/FixedPointMath.sol";

/// @author DELV
/// @title RETHHyperdrive
/// @notice The base contract for the RETH Hyperdrive implementation.
/// @dev Rocket Pool has it's own notion of shares to account for the accrual of
///      interest on the ether pooled in the Rocket Pool protocol. Instead of
///      maintaining a balance of shares, this integration can simply use Rocket Pool
///      shares directly.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract RETHBase is HyperdriveBase {
    using FixedPointMath for uint256;

    /// @dev The Rocket Pool storage contract.
    IRocketStorage internal immutable _rocketStorage;

    /// @notice Instantiates the RETH Hyperdrive base contract.
    /// @param __rocketStorage The Rocket Pool storage contract.
    constructor(IRocketStorage __rocketStorage) {
        _rocketStorage = __rocketStorage;
    }

    /// Yield Source ///

    /// @dev Accepts a transfer from the user in base or the yield source token.
    /// @param _amount The amount of token to transfer. It will be in either
    ///          base or shares depending on the `asBase` option.
    /// @param _options The options that configure the deposit. The only option
    ///        used in this implementation is "asBase" which determines if
    ///        the deposit is settled in ETH or RETH shares.
    /// @return shares The amount of shares that represents the amount deposited.
    /// @return vaultSharePrice The current vault share price.
    function _deposit(
        uint256 _amount,
        IHyperdrive.Options calldata _options
    ) internal override returns (uint256 shares, uint256 vaultSharePrice) {
        // Fetching the Rocket Deposit Pool address from the storage contract.
        address rocketDepositPoolAddress = _rocketStorage.getAddress(
            keccak256(abi.encodePacked("contract.address", "rocketDepositPool"))
        );
        IRocketDepositPool rocketDepositPool = IRocketDepositPool(
            rocketDepositPoolAddress
        );

        // Fetching the RETH token address from the storage contract.
        address rocketTokenRETHAddress = _rocketStorage.getAddress(
            keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"))
        );
        IRocketTokenRETH rocketTokenRETH = IRocketTokenRETH(
            rocketTokenRETHAddress
        );

        uint256 refund;
        if (_options.asBase) {
            // Ensure that sufficient ether was provided.
            if (msg.value < _amount) {
                revert IHyperdrive.TransferFailed();
            }

            // If the user sent more ether than the amount specified, refund the
            // excess ether.
            refund = msg.value - _amount;

            // The Deposit Pool's deposit function does not return a value, so the net
            // RETH minted needs to be calculated manually.
            uint256 rethBalanceBefore = rocketTokenRETH.balanceOf(
                address(this)
            );

            // Submit the provided ether to Rocket Pool to be deposited.
            rocketDepositPool.deposit{ value: _amount }();

            // Calculate the net shares minted.
            uint256 rethBalanceAfter = rocketTokenRETH.balanceOf(address(this));
            shares = rethBalanceAfter - rethBalanceBefore;

            // Calculate the vault share price.
            vaultSharePrice = _pricePerVaultShare();
        } else {
            // Refund any ether that was sent to the contract.
            refund = msg.value;

            // Transfer RETH shares into the contract.
            rocketTokenRETH.transferFrom(msg.sender, address(this), _amount);

            // Calculate the vault share price.
            shares = _amount;
            vaultSharePrice = _pricePerVaultShare();
        }

        // Return excess ether that was sent to the contract.
        if (refund > 0) {
            (bool success, ) = payable(msg.sender).call{ value: refund }("");
            if (!success) {
                revert IHyperdrive.TransferFailed();
            }
        }

        return (shares, vaultSharePrice);
    }

    /// @notice Processes a trader's withdrawal. This yield source supports
    ///         withdrawals in ETH and RETH shares.
    /// @param _shares The amount of shares to withdraw from Hyperdrive.
    /// @param _sharePrice The share price.
    /// @param _options The options that configure the withdrawal. The options
    ///        used in this implementation are "destination" which specifies the
    ///        recipient of the withdrawal and "asBase" which determines
    ///        if the withdrawal is settled in base or vault shares.
    /// @return The amount of shares withdrawn from the yield source.
    function _withdraw(
        uint256 _shares,
        uint256 _sharePrice,
        IHyperdrive.Options calldata _options
    ) internal override returns (uint256) {
        // Fetching the RETH token address from the storage contract.
        address rocketTokenRETHAddress = _rocketStorage.getAddress(
            keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"))
        );
        IRocketTokenRETH rocketTokenRETH = IRocketTokenRETH(
            rocketTokenRETHAddress
        );

        // NOTE: Round down to underestimate the base proceeds.
        //
        // Correct for any error that crept into the calculation of the share
        // amount by converting the shares to base and then back to shares
        // using the vault's share conversion logic.
        uint256 baseAmount = _shares.mulDown(_sharePrice);
        _shares = rocketTokenRETH.getRethValue(baseAmount);

        // If we're withdrawing zero shares, short circuit and return 0.
        if (_shares == 0) {
            return 0;
        }

        if (_options.asBase) {
            // The RETH token contract does not return the ether amount
            // that is burned in exchange for RETH, so this value has to be
            // fetched manually.
            uint256 ethAmount = rocketTokenRETH.getEthValue(_shares);

            // Burning RETH shares in exchange for ether.
            // Ether proceeds are credited to this contract.
            rocketTokenRETH.burn(_shares);

            // Return withdrawn ether to the destination.
            (bool success, ) = payable(_options.destination).call{
                value: ethAmount
            }("");

            if (!success) {
                revert IHyperdrive.TransferFailed();
            }
        } else {
            // Transfer the RETH shares to the destination.
            rocketTokenRETH.transfer(_options.destination, _shares);
        }

        return _shares;
    }

    /// @dev Returns the current vault share price. We simply use Rocket Pool's
    ///      internal share price.
    /// @return price The current vault share price.
    function _pricePerVaultShare()
        internal
        view
        override
        returns (uint256 price)
    {
        // Fetching the RETH token address from the storage contract.
        address rocketTokenRETHAddress = _rocketStorage.getAddress(
            keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"))
        );
        IRocketTokenRETH rocketTokenRETH = IRocketTokenRETH(
            rocketTokenRETHAddress
        );

        // Returns the value of one RETH token in ETH.
        return rocketTokenRETH.getExchangeRate();
    }

    /// @dev We override the message value check since this integration is
    ///      payable.
    function _checkMessageValue() internal pure override {}
}
