// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IL2Pool } from "../../interfaces/IAave.sol";
import { HyperdriveTarget0 } from "../../external/HyperdriveTarget0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { AAVE_L2_HYPERDRIVE_KIND } from "../../libraries/Constants.sol";
import { AaveL2Base } from "./AaveL2Base.sol";

/// @author DELV
/// @title AaveL2Target0
/// @notice AaveL2Hyperdrive's target0 logic contract. This contract contains
///         all of the getters for Hyperdrive as well as some stateful
///         functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract AaveL2Target0 is HyperdriveTarget0, AaveL2Base {
    /// @notice Initializes the target0 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController
    ) HyperdriveTarget0(_config, __adminController) {}

    /// @notice Returns the instance's kind.
    /// @return The instance's kind.
    function kind() external pure override returns (string memory) {
        _revert(abi.encode(AAVE_L2_HYPERDRIVE_KIND));
    }

    /// @notice Gets the AaveL2 pool used as this pool's yield source.
    /// @return The AaveL2 pool.
    function vault() external view returns (IL2Pool) {
        _revert(abi.encode(_vault));
    }
}
