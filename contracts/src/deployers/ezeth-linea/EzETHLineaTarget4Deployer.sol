// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { EzETHLineaTarget4 } from "../../instances/ezeth-linea/EzETHLineaTarget4.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveTargetDeployer } from "../../interfaces/IHyperdriveTargetDeployer.sol";
import { IXRenzoDeposit } from "../../interfaces/IXRenzoDeposit.sol";

/// @author DELV
/// @title EzETHLineaTarget4Deployer
/// @notice The target4 deployer for the EzETHLineaHyperdrive implementation.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract EzETHLineaTarget4Deployer is IHyperdriveTargetDeployer {
    /// @dev The Renzo deposit contract on Linea. The latest mint rate is used
    ///      as the vault share price.
    IXRenzoDeposit public immutable xRenzoDeposit;

    /// @notice Instantiates the ezETH Linea Hyperdrive base contract.
    /// @param _xRenzoDeposit The xRenzoDeposit contract that provides the
    ///        vault share price.
    constructor(IXRenzoDeposit _xRenzoDeposit) {
        xRenzoDeposit = _xRenzoDeposit;
    }

    /// @notice Deploys a target4 instance with the given parameters.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _salt The create2 salt used in the deployment.
    /// @return The address of the newly deployed EzETHLineaTarget4 instance.
    function deployTarget(
        IHyperdrive.PoolConfig memory _config,
        bytes memory, // unused  _extraData
        bytes32 _salt
    ) external returns (address) {
        return
            address(
                // NOTE: We hash the sender with the salt to prevent the
                // front-running of deployments.
                new EzETHLineaTarget4{
                    salt: keccak256(abi.encode(msg.sender, _salt))
                }(_config, xRenzoDeposit)
            );
    }
}