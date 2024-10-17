// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { DataTypes } from "aave/protocol/libraries/types/DataTypes.sol";
import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { IL2Pool } from "../../interfaces/IAave.sol";
import { IAL2Token } from "../../interfaces/IAL2Token.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { HyperdriveBase } from "../../internal/HyperdriveBase.sol";
import { FixedPointMath } from "../../libraries/FixedPointMath.sol";
import { SafeCast } from "../../libraries/SafeCast.sol";
import { AaveL2Conversions } from "./AaveL2Conversions.sol";

/// @author DELV
/// @title AaveL2Base
/// @notice The base contract for the AaveL2 Hyperdrive implementation.
/// @dev This Hyperdrive implementation is designed to work with standard
///      AaveL2 vaults. Non-standard implementations may not work correctly
///      and should be carefully checked.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract AaveL2Base is HyperdriveBase {
    using FixedPointMath for uint256;
    using SafeCast for uint256;
    using SafeERC20 for ERC20;

    /// @dev The AaveL2 vault that is this instance's yield source.
    IL2Pool internal immutable _vault;

    /// @notice Instantiates the AaveL2Hyperdrive base contract.
    constructor() {
        // Initialize the AaveL2 vault immutable.
        _vault = IAL2Token(address(_vaultSharesToken)).POOL();

        // Approve the AaveL2 vault with 1 wei. This ensures that all of the
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
        // NOTE: We use the encoded params version of 'supply' for better gas
        // efficiency.
        bytes32 supplyParams = encodeSupplyParams(
            address(_baseToken),
            _baseAmount,
            0
        );
        _vault.supply(supplyParams);

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
    /// @return amountWithdrawn The amount of base withdrawn.
    function _withdrawWithBase(
        uint256 _shareAmount,
        address _destination, // unused _destination,
        bytes calldata // unused
    ) internal override returns (uint256 amountWithdrawn) {
        // Withdraw assets from the AaveL2 vault to the destination.
        bytes32 withdrawParams = encodeWithdrawParams(
            address(_baseToken),
            _convertToBase(_shareAmount)
        );
        amountWithdrawn = _vault.withdraw(withdrawParams);
        _baseToken.transfer(_destination, amountWithdrawn);

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
        return
            AaveL2Conversions.convertToBase(_baseToken, _vault, _shareAmount);
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function _convertToShares(
        uint256 _baseAmount
    ) internal view override returns (uint256) {
        return
            AaveL2Conversions.convertToShares(_baseToken, _vault, _baseAmount);
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

    /// @notice Encodes supply parameters from standard input to compact
    ///         representation of 1 bytes32.
    /// @dev Without an onBehalfOf parameter as the compact calls to L2Pool will
    ///      use msg.sender as onBehalfOf.
    /// @param asset The address of the underlying asset to supply.
    /// @param amount The amount to be supplied.
    /// @param referralCode referralCode Code used to register the integrator
    ///        originating the operation, for potential rewards. 0 if the action
    ///        is executed directly by the user, without any middle-man.
    /// @return Compact representation of supply parameters.
    function encodeSupplyParams(
        address asset,
        uint256 amount,
        uint16 referralCode
    ) internal view returns (bytes32) {
        uint16 assetId = _vault.getReserveData(asset).id;
        uint128 shortenedAmount = amount.toUint128();
        bytes32 res;
        assembly {
            res := add(
                assetId,
                add(shl(16, shortenedAmount), shl(144, referralCode))
            )
        }
        return res;
    }

    /// @notice Encodes withdraw parameters from standard input to compact
    ///         representation of 1 bytes32.
    /// @dev Without a to parameter as the compact calls to L2Pool will use
    ///      msg.sender as to.
    /// @param asset The address of the underlying asset to withdraw.
    /// @param amount The underlying amount to be withdrawn.
    /// @return compact representation of withdraw parameters.
    function encodeWithdrawParams(
        address asset,
        uint256 amount
    ) internal view returns (bytes32) {
        DataTypes.ReserveDataLegacy memory data = _vault.getReserveData(asset);
        uint16 assetId = data.id;
        uint128 shortenedAmount = amount == type(uint256).max
            ? type(uint128).max
            : uint128(amount);

        bytes32 res;
        assembly {
            res := add(assetId, shl(16, shortenedAmount))
        }
        return res;
    }
}
