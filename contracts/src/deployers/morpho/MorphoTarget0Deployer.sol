// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { MorphoTarget0 } from "../../instances/morpho/MorphoTarget0.sol";
import { IMorpho } from "../../interfaces/IMorpho.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";
import { IMorpho, MarketParams } from "../../interfaces/IMorpho.sol";

/// @author DELV
/// @title MorphoTarget0Deployer
/// @notice The target0 deployer for the MorphoHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MorphoTarget0Deployer is IHyperdriveTargetDeployer {
    IMorpho internal immutable _morpho;
    MarketParams internal _marketParams;

    /// @notice Instantiates the core deployer.
    /// @param __morpho The Morpho contract.
    /// @param __marketParams The Morpho market information.
    constructor(IMorpho __morpho, MarketParams memory __marketParams) {
        _morpho = __morpho;
        _marketParams = __marketParams;
    }

    /// @notice Deploys a target0 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed MorphoTarget0 instance.
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes memory, // unused _extraData
        bytes32 _salt
    ) external returns (address) {
        return
            address(
                // NOTE: We hash the sender with the salt to prevent the
                // front-running of deployments.
                new MorphoTarget0{
                    salt: keccak256(abi.encode(msg.sender, _salt))
                }(_config, _morpho, _marketParams)
            );
    }
}
