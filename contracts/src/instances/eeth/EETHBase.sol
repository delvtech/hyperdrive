// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IEETH } from "../../interfaces/IEETH.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { ILiquidityPool } from "../../interfaces/ILiquidityPool.sol";
import { HyperdriveBase } from "../../internal/HyperdriveBase.sol";
import { EETHConversions } from "./EETHConversions.sol";

/// @author DELV
/// @title EETHBase
/// @notice The base contract for the EETH Hyperdrive implementation.
/// @dev This Hyperdrive implementation is designed to work with standard
///      EETH vaults. Non-standard implementations may not work correctly
///      and should be carefully checked.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract EETHBase is HyperdriveBase {
    /// @dev The Etherfi liquidity pool.
    ILiquidityPool public immutable _liquidityPool;

    /// @notice Instantiates the EETH Hyperdrive base contract.
    /// @param __liquidityPool The Etherfi liquidity pool contract.
    constructor(ILiquidityPool __liquidityPool) {
        _liquidityPool = __liquidityPool;
    }

    /// Yield Source ///

    /// @dev Accepts a deposit from the user in base.
    /// @param _baseAmount The base amount to deposit.
    /// @return sharesMinted The shares that were minted in the deposit.
    /// @return refund The amount of ETH to refund.
    function _depositWithBase(
        uint256 _baseAmount,
        bytes calldata // unused
    ) internal override returns (uint256 sharesMinted, uint256 refund) {
        // Ensure that sufficient ether was provided.
        if (msg.value < _baseAmount) {
            revert IHyperdrive.TransferFailed();
        }

        // If the user sent more ether than the amount specified, refund the
        // excess ether.
        unchecked {
            refund = msg.value - _baseAmount;
        }

        // Deposit the base into the yield source.
        sharesMinted = _liquidityPool.deposit{ value: _baseAmount }(
            _adminController.feeCollector()
        );
        return (sharesMinted, refund);
    }

    /// @dev Process a deposit in vault shares.
    /// @param _shareAmount The vault shares amount to deposit.
    function _depositWithShares(
        uint256 _shareAmount,
        bytes calldata // unused _extraData
    ) internal override {
        // Convert the vault shares to base.
        uint256 baseAmount = _convertToBase(_shareAmount);

        // NOTE: The eETH transferFrom function converts from base to shares under
        // the hood using `sharesForAmount(_amount)`.
        //
        // Take custody of the deposit in vault shares.
        bool result = IEETH(address(_vaultSharesToken)).transferFrom(
            msg.sender,
            address(this),
            baseAmount
        );
        if (!result) {
            revert IHyperdrive.TransferFailed();
        }
    }

    /// @dev Process a withdrawal in base and send the proceeds to the
    ///      destination.
    function _withdrawWithBase(
        uint256, // unused
        address, // unused
        bytes calldata // unused
    ) internal pure override returns (uint256) {
        // eETH withdrawals aren't necessarily instantaneous. Users that want
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
        // Convert the vault shares to base.
        uint256 baseAmount = _convertToBase(_shareAmount);

        // NOTE: The eETH transfer function converts from base to shares under
        // the hood using `sharesForAmount(_amount)`.
        //
        // Transfer the eETH to the destination.
        bool result = IEETH(address(_vaultSharesToken)).transfer(
            _destination,
            baseAmount
        );
        if (!result) {
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
            EETHConversions.convertToBase(
                _liquidityPool,
                _vaultSharesToken,
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
            EETHConversions.convertToShares(
                _liquidityPool,
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
    ///      payable.
    function _checkMessageValue() internal pure override {}
}
