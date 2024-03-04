// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { HyperdriveTarget0 } from "../../external/HyperdriveTarget0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IERC20 } from "../../interfaces/IERC20.sol";
import { IRocketStorage } from "../../interfaces/IRocketStorage.sol";
import { IRocketTokenRETH } from "../../interfaces/IRocketTokenRETH.sol";
import { RETHBase } from "./RETHBase.sol";

/// @author DELV
/// @title RETHTarget0
/// @notice RETHHyperdrive's target0 logic contract. This contract contains
///         all of the getters for Hyperdrive as well as some stateful
///         functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract RETHTarget0 is HyperdriveTarget0, RETHBase {
    using SafeERC20 for ERC20;

    /// @notice Initializes the target0 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __rocketStorage The Rocket Pool storage contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IRocketStorage __rocketStorage
    ) HyperdriveTarget0(_config) RETHBase(__rocketStorage) {}

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

        // Fetching the RETH token address from the storage contract.
        address rocketTokenRETHAddress = _rocketStorage.getAddress(
            keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"))
        );
        IRocketTokenRETH rocketTokenRETH = IRocketTokenRETH(
            rocketTokenRETHAddress
        );

        // Ensure that the target isn't the RETH token.
        if (address(_target) == rocketTokenRETHAddress) {
            revert IHyperdrive.UnsupportedToken();
        }

        // Get Hyperdrive's balance of RETH tokens prior to sweeping.
        uint256 rethBalance = rocketTokenRETH.balanceOf(address(this));

        // Transfer the entire balance of the sweep target to the fee collector.
        uint256 balance = _target.balanceOf(address(this));
        ERC20(address(_target)).safeTransfer(_feeCollector, balance);

        // Ensure that the stETH balance hasn't changed.
        if (rocketTokenRETH.balanceOf(address(this)) != rethBalance) {
            revert IHyperdrive.SweepFailed();
        }
    }

    /// Getters ///

    /// @notice Returns the MultiToken's decimals.
    /// @return The MultiToken's decimals.
    function decimals() external pure override returns (uint8) {
        _revert(abi.encode(uint8(18)));
    }
}
