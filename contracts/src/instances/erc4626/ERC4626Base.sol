// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "../../interfaces/IERC4626.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IERC4626Hyperdrive } from "../../interfaces/IERC4626Hyperdrive.sol";
import { HyperdriveBase } from "../../internal/HyperdriveBase.sol";
import { FixedPointMath, ONE } from "../../libraries/FixedPointMath.sol";

/// @author DELV
/// @title ERC4626Base
/// @notice The base contract for the ERC4626 Hyperdrive implementation.
/// @dev This Hyperdrive implementation is designed to work with standard
///      ERC4626 vaults. Non-standard implementations may not work correctly
///      and should be carefully checked.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract ERC4626Base is HyperdriveBase {
    using FixedPointMath for uint256;
    using SafeERC20 for ERC20;

    /// @dev The ERC4626 vault that this pool uses as a yield source.
    IERC4626 internal immutable _vault;

    /// @notice Instantiates the ERC4626 Hyperdrive base contract.
    /// @param __vault The ERC4626 compatible vault.
    constructor(IERC4626 __vault) {
        // Initialize the pool immutable.
        _vault = __vault;
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
        uint256 sharesMinted = _vault.deposit(_baseAmount, address(this));

        return (sharesMinted, 0);
    }

    /// @dev Process a deposit in vault shares.
    /// @param _shareAmount The vault shares amount to deposit.
    function _depositWithShares(
        uint256 _shareAmount,
        bytes calldata // unused
    ) internal override {
        // Take custody of the deposit in vault shares.
        ERC20(address(_vault)).safeTransferFrom(
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
        // Redeem from the yield source and transfer the
        // resulting base to the destination address.
        amountWithdrawn = _vault.redeem(
            _shareAmount,
            _destination,
            address(this)
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
        // Transfer vault shares to the destination.
        ERC20(address(_vault)).safeTransfer(_destination, _shareAmount);
    }

    /// @dev Ensure that ether wasn't sent because ERC4626 vaults don't support
    ///      deposits of ether.
    function _checkMessageValue() internal view override {
        if (msg.value != 0) {
            revert IHyperdrive.NotPayable();
        }
    }

    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function _convertToBase(
        uint256 _shareAmount
    ) internal view override returns (uint256) {
        return _vault.convertToAssets(_shareAmount);
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function _convertToShares(
        uint256 _baseAmount
    ) internal view override returns (uint256) {
        return _vault.convertToShares(_baseAmount);
    }
}
