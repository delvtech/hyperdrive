// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { HyperdriveExtras } from "../HyperdriveExtras.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";

// TODO: Polish the comments as part of #621.
//
/// @author DELV
/// @title ERC4626Extras
/// @notice The extras contract for ERC4626Hyperdrive instances.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626Extras is HyperdriveExtras {
    using SafeERC20 for IERC20;

    /// @dev The yield source contract for this hyperdrive
    IERC4626 internal immutable pool;

    /// @dev A mapping from addresses to their status as a sweep target. This
    ///      mapping does not change after construction.
    mapping(address target => bool canSweep) internal isSweepable;

    /// @notice Initializes a Hyperdrive pool.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The address of the factory which is used to deploy
    ///        the ERC20 linker contracts.
    /// @param _pool The ERC4626 compatible yield source.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        IERC4626 _pool
    ) HyperdriveExtras(_config, _linkerCodeHash, _linkerFactory) {
        // Initialize the pool immutable.
        pool = _pool;
    }

    /// Yield Source ///

    /// @notice Processes a trader's withdrawal in either base or vault shares.
    ///         If the withdrawal is settled in base, the base will need to be
    ///         withdrawn from the yield source.
    /// @param _shares The amount of shares to withdraw from Hyperdrive.
    /// @param _options The options that configure the withdrawal. The options
    ///        used in this implementation are "destination" which specifies the
    ///        recipient of the withdrawal and "asBase" which determines
    ///        if the withdrawal is settled in base or vault shares.
    /// @return amountWithdrawn The amount withdrawn from the yield source.
    function _withdraw(
        uint256 _shares,
        IHyperdrive.Options calldata _options
    ) internal override returns (uint256 amountWithdrawn) {
        if (_options.asBase) {
            // Redeem the shares from the yield source and transfer the
            // resulting base to the destination address.
            amountWithdrawn = pool.redeem(
                _shares,
                _options.destination,
                address(this)
            );
        } else {
            // Transfer vault shares to the destination.
            IERC20(address(pool)).safeTransfer(_options.destination, _shares);
            // Estimate the amount of base that was withdrawn from the yield
            // source.
            uint256 estimated = pool.convertToAssets(_shares);
            amountWithdrawn = estimated;
        }
    }

    /// Extras ///

    /// @notice Some yield sources [eg Morpho] pay rewards directly to this
    ///         contract but we can't handle distributing them internally so we
    ///         sweep to the fee collector address to then redistribute to users.
    /// @dev WARN: The entire balance of any of the sweep targets can be swept
    ///      by governance. If these sweep targets provide access to the base or
    ///      pool token, then governance has the ability to rug the pool.
    /// @dev WARN: It is unlikely but possible that there is a selector overlap
    ///      with 'transferFrom'. Any integrating contracts should be checked
    ///      for that, as it may result in an unexpected call from this address.
    /// @param _target The token to sweep.
    function sweep(IERC20 _target) external {
        // Ensure that the sender is the fee collector or a pauser.
        if (msg.sender != _feeCollector && !_pausers[msg.sender])
            revert IHyperdrive.Unauthorized();

        // Ensure that thet target can be swept by governance.
        if (!isSweepable[address(_target)]) {
            revert IHyperdrive.UnsupportedToken();
        }

        // Transfer the entire balance of the sweep target to the fee collector.
        uint256 balance = _target.balanceOf(address(this));
        _target.safeTransfer(_feeCollector, balance);
    }
}
