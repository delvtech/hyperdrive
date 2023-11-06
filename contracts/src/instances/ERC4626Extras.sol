// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { HyperdriveExtras } from "../HyperdriveExtras.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { ERC4626Base } from "./ERC4626Base.sol";

// TODO: Polish the comments as part of #621.
//
/// @author DELV
/// @title ERC4626Extras
/// @notice The extras contract for ERC4626Hyperdrive instances.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626Extras is HyperdriveExtras, ERC4626Base {
    using SafeTransferLib for IERC20;

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
    )
        HyperdriveExtras(_config, _linkerCodeHash, _linkerFactory)
        ERC4626Base(_pool)
    {}

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
        SafeTransferLib.safeTransfer(
            ERC20(address(_target)),
            _feeCollector,
            balance
        );
    }
}
