// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { ChainlinkTarget1 } from "../../instances/chainlink/ChainlinkTarget1.sol";
import { IChainlinkAggregatorV3 } from "../../interfaces/IChainlinkAggregatorV3.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";

/// @author DELV
/// @title ChainlinkTarget1Deployer
/// @notice The target1 deployer for the ChainlinkHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ChainlinkTarget1Deployer is IHyperdriveTargetDeployer {
    /// @notice Deploys a target1 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param _extraData The extra data containing the Chainlink aggregator.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed ChainlinkTarget1 instance.
    function deployTarget(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController _adminController,
        bytes memory _extraData,
        bytes32 _salt
    ) external returns (address) {
        (IChainlinkAggregatorV3 aggregator, uint8 decimals) = abi.decode(
            _extraData,
            (IChainlinkAggregatorV3, uint8)
        );
        return
            address(
                // NOTE: We hash the sender with the salt to prevent the
                // front-running of deployments.
                new ChainlinkTarget1{
                    salt: keccak256(abi.encode(msg.sender, _salt))
                }(_config, _adminController, aggregator, decimals)
            );
    }
}
