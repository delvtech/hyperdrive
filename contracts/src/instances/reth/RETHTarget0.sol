// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { HyperdriveTarget0 } from "../../external/HyperdriveTarget0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
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
    /// @dev The instance's name.
    string internal constant NAME = "RETHHyperdrive";

    /// @dev The instance's version.
    string internal constant VERSION = "v1.0.0";

    /// @notice Initializes the target0 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    constructor(
        IHyperdrive.PoolConfig memory _config
    ) HyperdriveTarget0(_config) {}

    /// Getters ///

    /// @notice Returns the instance's name.
    /// @return The instance's name.
    function name() external pure override returns (string memory) {
        _revert(abi.encode(NAME));
    }

    /// @notice Returns the instance's version.
    /// @return The instance's version.
    function version() external pure override returns (string memory) {
        _revert(abi.encode(VERSION));
    }

    /// @notice Returns the MultiToken's decimals.
    /// @return The MultiToken's decimals.
    function decimals() external pure override returns (uint8) {
        _revert(abi.encode(uint8(18)));
    }
}
