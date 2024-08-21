// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IPool } from "aave/interfaces/IPool.sol";
import { HyperdriveTarget0 } from "../../external/HyperdriveTarget0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { AAVE_HYPERDRIVE_KIND } from "../../libraries/Constants.sol";
import { AaveBase } from "./AaveBase.sol";

/// @author DELV
/// @title AaveTarget0
/// @notice AaveHyperdrive's target0 logic contract. This contract contains
///         all of the getters for Hyperdrive as well as some stateful
///         functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract AaveTarget0 is HyperdriveTarget0, AaveBase {
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
        _revert(abi.encode(AAVE_HYPERDRIVE_KIND));
    }

    /// @notice Gets the Aave pool used as this pool's yield source.
    /// @return The Aave pool.
    function vault() external view returns (IPool) {
        _revert(abi.encode(_vault));
    }
}
