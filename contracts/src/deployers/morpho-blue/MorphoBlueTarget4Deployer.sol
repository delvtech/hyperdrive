// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IMorpho } from "morpho-blue/src/interfaces/IMorpho.sol";
import { MorphoBlueTarget4 } from "../../instances/morpho-blue/MorphoBlueTarget4.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";

/// @author DELV
/// @title MorphoBlueTarget4Deployer
/// @notice The target4 deployer for the MorphoBlueHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MorphoBlueTarget4Deployer is IHyperdriveTargetDeployer {
    /// @notice The Morpho Blue contract.
    IMorpho public immutable morpho;

    /// @notice Instantiates the core deployer.
    /// @param _morpho The Morpho Blue contract.
    constructor(IMorpho _morpho) {
        morpho = _morpho;
    }

    /// @notice Deploys a target4 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _extraData The extra data for the Morpho instance. This contains
    ///        the market parameters that weren't specified in the config.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed MorphoBlueTarget3 instance.
    function deployTarget(
        IHyperdrive.PoolConfig memory _config,
        bytes memory _extraData,
        bytes32 _salt
    ) external returns (address) {
        (
            address collateralToken,
            address oracle,
            address irm,
            uint256 lltv
        ) = abi.decode(_extraData, (address, address, address, uint256));
        return
            address(
                // NOTE: We hash the sender with the salt to prevent the
                // front-running of deployments.
                new MorphoBlueTarget4{
                    salt: keccak256(abi.encode(msg.sender, _salt))
                }(_config, morpho, collateralToken, oracle, irm, lltv)
            );
    }
}
