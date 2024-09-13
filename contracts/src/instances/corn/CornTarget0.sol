// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { HyperdriveTarget0 } from "../../external/HyperdriveTarget0.sol";
import { ICornSilo } from "../../interfaces/ICornSilo.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { CORN_HYPERDRIVE_KIND } from "../../libraries/Constants.sol";
import { CornBase } from "./CornBase.sol";

/// @author DELV
/// @title CornTarget0
/// @notice CornHyperdrive's target0 logic contract. This contract contains
///         all of the getters for Hyperdrive as well as some stateful
///         functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract CornTarget0 is HyperdriveTarget0, CornBase {
    /// @notice Initializes the target0 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param __cornSilo The Corn Silo contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController,
        ICornSilo __cornSilo
    ) HyperdriveTarget0(_config, __adminController) CornBase(__cornSilo) {}

    /// @notice Returns the instance's kind.
    /// @return The instance's kind.
    function kind() external pure override returns (string memory) {
        _revert(abi.encode(CORN_HYPERDRIVE_KIND));
    }

    /// @notice Returns the Corn Silo contract. This is where the base token
    ///         will be deposited.
    /// @return The Corn Silo contract.
    function cornSilo() external view returns (ICornSilo) {
        _revert(abi.encode(_cornSilo));
    }
}
