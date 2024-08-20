// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IHyperdrive } from "./IHyperdrive.sol";
import { IHyperdriveAdminController } from "./IHyperdriveAdminController.sol";

interface IHyperdriveTargetDeployer {
    /// @notice Deploys a target instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param _extraData The extra data that contains the pool and sweep targets.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed target instance.
    function deployTarget(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController _adminController,
        bytes memory _extraData,
        bytes32 _salt
    ) external returns (address);
}
