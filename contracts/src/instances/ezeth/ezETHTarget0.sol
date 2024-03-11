// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { HyperdriveTarget0 } from "../../external/HyperdriveTarget0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IERC20 } from "../../interfaces/IERC20.sol";
import { IRestakeManager } from "../../interfaces/IRestakeManager.sol";
import { ezETHBase } from "./ezETHBase.sol";

/// @author DELV
/// @title ezETHTarget0
/// @notice ezETHHyperdrive's target0 logic contract. This contract contains
///         all of the getters for Hyperdrive as well as some stateful
///         functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ezETHTarget0 is HyperdriveTarget0, ezETHBase {
    using SafeERC20 for ERC20;

    /// @notice Initializes the target0 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _restakeManager The Renzo contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IRestakeManager _restakeManager
    ) HyperdriveTarget0(_config) ezETHBase(_restakeManager) {}

    /// Extras ///

    /// @notice Transfers the contract's balance of a target token to the fee
    ///         collector address.
    /// @dev WARN: It is unlikely but possible that there is a selector overlap
    ///      with 'transferFrom'. Any integrating contracts should be checked
    ///      for that, as it may result in an unexpected call from this address.
    /// @param _target The target token to sweep.
    function sweep(IERC20 _target) external {
        // Ensure that the sender is the fee collector or a pauser.
        if (msg.sender != _feeCollector && !_pausers[msg.sender]) {
            revert IHyperdrive.Unauthorized();
        }

        // Ensure that thet target isn't the ezETH token.
        if (address(_target) == address(_restakeManager)) {
            revert IHyperdrive.UnsupportedToken();
        }

        // Get Hyperdrive's balance of ezETH tokens prior to sweeping.
        uint256 ezETHBalance = _restakeManager.balanceOf(address(this));

        // Transfer the entire balance of the sweep target to the fee collector.
        uint256 balance = _target.balanceOf(address(this));
        ERC20(address(_target)).safeTransfer(_feeCollector, balance);

        // Ensure that the ezETH balance hasn't changed.
        if (_restakeManager.balanceOf(address(this)) != ezETHBalance) {
            revert IHyperdrive.SweepFailed();
        }
    }

    /// Getters ///

    /// @notice Returns the Lido contract.
    /// @return lido The Lido contract.
    function lido() external view returns (ILido) {
        _revert(abi.encode(_restakeManager));
    }

    /// @notice Returns the MultiToken's decimals.
    /// @return The MultiToken's decimals.
    function decimals() external pure override returns (uint8) {
        _revert(abi.encode(uint8(18)));
    }
}
