// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { Create2 } from "openzeppelin/utils/Create2.sol";

/// @author DELV
/// @title HyperdriveCreate2Factory
/// @notice Uses Create2 to deploy a contract to a precomputable address that
///         is only dependent on the contract's bytecode and the provided salt.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract HyperdriveCreate2Factory {
    /// @notice Deploy the contract with the provided creation code to a
    ///         precomputable address determined by only the salt and bytecode.
    /// @param _salt Salt to use for the deployment.
    /// @param _creationCode Creation code of the contract to deploy.
    /// @return deployed Address of the deployed contract.
    function deploy(
        bytes32 _salt,
        bytes memory _creationCode
    ) external payable returns (address deployed) {
        return Create2.deploy(msg.value, _salt, _creationCode);
    }

    /// @notice Deploy the contract with the provided creation code to a
    ///         precomputable address determined by only the deployer address
    ///         and salt.
    /// @param _salt Salt to use for the deployment.
    /// @param _creationCode Creation code of the contract to deploy.
    /// @param _initializationCode Encoded function data to be called on the
    ///        newly deployed contract.
    /// @return deployed Address of the deployed contract.
    function deploy(
        bytes32 _salt,
        bytes memory _creationCode,
        bytes memory _initializationCode
    ) external payable returns (address deployed) {
        deployed = Create2.deploy(msg.value, _salt, _creationCode);
        (bool success, ) = deployed.call(_initializationCode);
        require(success, "FAILED_INITIALIZATION");
        return deployed;
    }

    /// @notice Use the deployer address and salt to compute the address of a
    ///         contract deployed via Create2.
    /// @param _salt Salt of the deployed contract.
    /// @param _bytecodeHash Hash of the contract bytecode.
    /// @return Address of the Create2 deployed contract.
    function getDeployed(
        bytes32 _salt,
        bytes32 _bytecodeHash
    ) external view returns (address) {
        return Create2.computeAddress(_salt, _bytecodeHash);
    }
}
