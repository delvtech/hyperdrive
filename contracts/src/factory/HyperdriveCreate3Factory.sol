// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { CREATE3 } from "solmate/utils/CREATE3.sol";

/// @author DELV
/// @title HyperdriveCreate3Factory
/// @notice Uses CREATE3 to deploy a contract to a precomputable address that
///         is only dependent on the deployer's address and the provided salt.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract HyperdriveCreate3Factory {
    /// @notice Deploy the contract with the provided creation code to a
    ///         precomputable address determined by only the deployer address
    ///         and salt.
    /// @param _salt Salt to use for the deployment.
    /// @param _creationCode Creation code of the contract to deploy.
    function deploy(
        bytes32 _salt,
        bytes memory _creationCode
    ) external payable returns (address deployed) {
        // Include the deployer's address as part of the salt to prevent
        // frontrunning and give deployers their own "namespaces".
        _salt = keccak256(abi.encodePacked(msg.sender, _salt));
        return CREATE3.deploy(_salt, _creationCode, msg.value);
    }

    /// @notice Use the deployer address and salt to compute the address of a
    ///         contract deployed via CREATE3.
    /// @param _deployer Address of the contract deployer.
    /// @param _salt Salt of the deployed contract.
    /// @return Address of the CREATE3 deployed contract.
    function getDeployed(
        address _deployer,
        bytes32 _salt
    ) external view returns (address) {
        _salt = keccak256(abi.encodePacked(_deployer, _salt));
        return CREATE3.getDeployed(_salt, _deployer);
    }
}
