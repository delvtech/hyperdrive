// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IERC4626Hyperdrive } from "../interfaces/IERC4626Hyperdrive.sol";
import { HyperdriveBase } from "../internal/HyperdriveBase.sol";
import { FixedPointMath, ONE } from "../libraries/FixedPointMath.sol";

/// @author DELV
/// @title ERC4626Base
/// @notice The base contract for the ERC4626 Hyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract ERC4626Base is HyperdriveBase {
    using FixedPointMath for uint256;
    using SafeTransferLib for ERC20;

    /// @dev The yield source contract for this hyperdrive.
    IERC4626 internal immutable _pool;

    /// @dev A mapping from addresses to their status as a sweep target. This
    ///      mapping does not change after construction.
    mapping(address target => bool canSweep) internal _isSweepable;

    /// @notice Instantiates the ERC4626 Hyperdrive base contract.
    /// @param __pool The ERC4626 compatible yield source.
    constructor(IERC4626 __pool) {
        // Initialize the pool immutable.
        _pool = __pool;
    }

    /// Yield Source ///

    /// @notice Accepts a trader's deposit in either base or vault shares. If
    ///         the deposit is settled in base, the base is deposited into the
    ///         yield source immediately.
    /// @param _amount The amount of token to transfer. It will be in either
    ///          base or shares depending on the `asBase` option.
    /// @param _options The options that configure the deposit. The only option
    ///        used in this implementation is "asBase" which determines if
    ///        the deposit is settled in base or vault shares.
    /// @return sharesMinted The shares this deposit creates.
    /// @return sharePrice The share price at time of deposit.
    function _deposit(
        uint256 _amount,
        IHyperdrive.Options calldata _options
    ) internal override returns (uint256 sharesMinted, uint256 sharePrice) {
        if (_options.asBase) {
            // Take custody of the deposit in base.
            ERC20(address(_baseToken)).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );

            // Deposit the base into the yield source.
            ERC20(address(_baseToken)).safeApprove(address(_pool), _amount);
            sharesMinted = _pool.deposit(_amount, address(this));
        } else {
            // WARN: This logic doesn't account for slippage in the conversion
            // from base to shares. If deposits to the yield source incur
            // slippage, this logic will be incorrect.
            sharesMinted = _amount;

            // Take custody of the deposit in vault shares.
            ERC20(address(_pool)).safeTransferFrom(
                msg.sender,
                address(this),
                sharesMinted
            );
        }
        sharePrice = _pricePerShare();
    }

    /// @notice Processes a trader's withdrawal in either base or vault shares.
    ///         If the withdrawal is settled in base, the base will need to be
    ///         withdrawn from the yield source.
    /// @param _shares The amount of shares to withdraw from Hyperdrive.
    /// @param _options The options that configure the withdrawal. The options
    ///        used in this implementation are "destination" which specifies the
    ///        recipient of the withdrawal and "asBase" which determines
    ///        if the withdrawal is settled in base or vault shares.
    /// @return amountWithdrawn The amount withdrawn from the yield source.
    ///         it will be in either base or shares depending on the `asBase`
    ///         option.
    function _withdraw(
        uint256 _shares,
        IHyperdrive.Options calldata _options
    ) internal override returns (uint256 amountWithdrawn) {

        // Just return zero in this case
        if ( _shares == 0 ) {
            return 0;
        }

        if (_options.asBase) {
            // Redeem from the yield source and transfer the
            // resulting base to the destination address.
            amountWithdrawn = _pool.redeem(
                _shares,
                _options.destination,
                address(this)
            );
        } else {
            // Transfer vault shares to the destination.
            ERC20(address(_pool)).safeTransfer(_options.destination, _shares);
            amountWithdrawn = _shares;
        }
    }

    /// @notice Loads the share price from the yield source.
    /// @return The current share price.
    /// @dev must remain consistent with the impl inside of the DataProvider
    function _pricePerShare() internal view override returns (uint256) {
        return _pool.convertToAssets(ONE);
    }

    /// @dev Ensure that ether wasn't sent because ERC4626 vaults don't support
    ///      deposits of ether.
    function _checkMessageValue() internal view override {
        if (msg.value != 0) {
            revert IHyperdrive.NotPayable();
        }
    }
}
