// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { HyperdriveTarget0 } from "../../external/HyperdriveTarget0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { MorphoBase } from "./MorphoBase.sol";

/// @author DELV
/// @title MorphoTarget0
/// @notice MorphoHyperdrive's target0 logic contract. This contract contains
///         all of the getters for Hyperdrive as well as some stateful
///         functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MorphoTarget0 is HyperdriveTarget0, MorphoBase {
    /// @dev The instance's name.
    string internal constant NAME = "MorphoHyperdrive";

    /// @notice Initializes the target0 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    constructor(
        IHyperdrive.PoolConfig memory _config
    ) HyperdriveTarget0(_config) {}

    /// @notice Returns the instance's name.
    /// @return The instance's name.
    function name() external pure override returns (string memory) {
        _revert(abi.encode(NAME));
    }
}
