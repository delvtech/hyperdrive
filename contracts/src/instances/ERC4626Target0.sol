// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { HyperdriveTarget0 } from "../external/HyperdriveTarget0.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { ERC4626Base } from "./ERC4626Base.sol";

/// @author DELV
/// @title ERC4626Target0
/// @notice ERC4626Hyperdrive's target 0 logic contract. This contract contains
///         all of the getters for Hyperdrive as well as some stateful
///         functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626Target0 is HyperdriveTarget0, ERC4626Base {
    using SafeTransferLib for ERC20;

    /// @notice Initializes the target0 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __pool The ERC4626 pool.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IERC4626 __pool
    ) HyperdriveTarget0(_config) ERC4626Base(__pool) {}

    /// Extras ///

    /// @notice Some yield sources [eg Morpho] pay rewards directly to this
    ///         contract but we can't handle distributing them internally so we
    ///         sweep to the fee collector address to then redistribute to users.
    /// @dev WARN: It is unlikely but possible that there is a selector overlap
    ///      with 'transferFrom'. Any integrating contracts should be checked
    ///      for that, as it may result in an unexpected call from this address.
    /// @param _target The token to sweep.
    function sweep(IERC20 _target) external {
        // Ensure that the sender is the fee collector or a pauser.
        if (msg.sender != _feeCollector && !_pausers[msg.sender]) {
            revert IHyperdrive.Unauthorized();
        }

        // Ensure that thet target isn't the base or vault token
        if (
            address(_target) == address(_baseToken) ||
            address(_target) == address(_pool)
        ) {
            revert IHyperdrive.UnsupportedToken();
        }

        // Get Hyperdrive's balance of the base and pool tokens prior to
        // sweeping.
        uint256 baseBalance = _baseToken.balanceOf(address(this));
        uint256 poolBalance = _pool.balanceOf(address(this));

        // Transfer the entire balance of the sweep target to the fee collector.
        uint256 balance = _target.balanceOf(address(this));
        ERC20(address(_target)).safeTransfer(_feeCollector, balance);

        // Ensure that the base and pool balances haven't changed.
        if (
            _baseToken.balanceOf(address(this)) != baseBalance ||
            _pool.balanceOf(address(this)) != poolBalance
        ) {
            revert IHyperdrive.SweepFailed();
        }
    }

    /// Getters ///

    /// @notice Gets the 4626 pool.
    /// @return The 4626 pool.
    function pool() external view returns (IERC4626) {
        _revert(abi.encode(_pool));
    }
}
