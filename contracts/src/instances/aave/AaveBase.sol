// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IAToken } from "aave/interfaces/IAToken.sol";
import { WadRayMath } from "aave/protocol/libraries/math/WadRayMath.sol";
import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "../../interfaces/IERC4626.sol";
import { IAave } from "../../interfaces/IAave.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { HyperdriveBase } from "../../internal/HyperdriveBase.sol";

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
    using SafeERC20 for ERC20;
    using WadRayMath for uint256;

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
        // ****************************************************************
        // FIXME: Implement this for new instances. ERC4626 example provided.
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
            address(_vaultSharesToken),
            _baseAmount + 1
        );
        uint256 sharesMinted = IERC4626(address(_vaultSharesToken)).deposit(
            _baseAmount,
            address(this)
        );

        return (sharesMinted, 0);
        // ****************************************************************
    }

    /// @dev Process a deposit in vault shares.
    /// @param _shareAmount The vault shares amount to deposit.
    function _depositWithShares(
        uint256 _shareAmount,
        bytes calldata // unused _extraData
    ) internal override {
        // ****************************************************************
        // FIXME: Implement this for new instances. ERC20 example provided.
        // Take custody of the deposit in vault shares.
        ERC20(address(_vaultSharesToken)).safeTransferFrom(
            msg.sender,
            address(this),
            _shareAmount
        );
        // ****************************************************************
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
        // ****************************************************************
        // FIXME: Implement this for new instances. ERC4626 example provided.
        // Redeem from the yield source and transfer the
        // resulting base to the destination address.
        amountWithdrawn = IERC4626(address(_vaultSharesToken)).redeem(
            _shareAmount,
            _destination,
            address(this)
        );

        return amountWithdrawn;
        // ****************************************************************
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
        // ****************************************************************
        // FIXME: Implement this for new instances. ERC20 example provided.
        // Transfer vault shares to the destination.
        ERC20(address(_vaultSharesToken)).safeTransfer(
            _destination,
            _shareAmount
        );
        // ****************************************************************
    }

    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function _convertToBase(
        uint256 _shareAmount
    ) internal view override returns (uint256) {
        // FIXME: To convert from shares to base, we're really converting from
        //        scaled amounts to amounts. We have that:
        //
        //        totalSupply = scaledTotalSupply.rayMul(index)
        //
        //        and
        //
        //        amount = scaledAmount.rayMul(index)
        //
        //        so
        //
        //        amount = scaledAmount.rayMul(totalSupply.rayDiv(scaledTotalSupply))

        // FIXME: Cache the POOL address.
        //
        // FIXME: Verify on construction that _baseToken == IAToken(address(_vaultSharesToken)).UNDERLYING_ASSET_ADDRESS()

        // Aave's AToken accounting calls shares "scaled tokens." We can convert
        // from scaled tokens to aTokens with the formula:
        //
        // aToken = scaledToken.rayMul(POOL.getReserveNormalizedIncome(_underlyingAsset))
        //
        // `rayMul` computes a 27 decimal fixed point multiplication and
        // `_underlyingAsset` is the base token address.
        IAToken vaultSharesToken = IAToken(address(_vaultSharesToken));
        return
            _shareAmount.rayMul(
                vaultSharesToken.POOL().getReserveNormalizedIncome(
                    address(_baseToken)
                )
            );
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function _convertToShares(
        uint256 _baseAmount
    ) internal view override returns (uint256) {
        // ****************************************************************
        // FIXME: Implement this for new instances.
        return
            IERC4626(address(_vaultSharesToken)).convertToShares(_baseAmount);
        // ****************************************************************
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
