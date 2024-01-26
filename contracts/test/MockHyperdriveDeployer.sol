// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployerCoordinator } from "contracts/src/interfaces/IHyperdriveDeployerCoordinator.sol";
import { IHyperdriveTargetDeployer } from "contracts/src/interfaces/IHyperdriveTargetDeployer.sol";
import { MockHyperdrive } from "./MockHyperdrive.sol";

contract MockHyperdriveDeployer is IHyperdriveDeployerCoordinator {
    function deploy(
        IHyperdrive.PoolDeployConfig memory _deployConfig,
        bytes memory
    ) external override returns (address) {
        IHyperdrive.PoolConfig memory _config;

        // Copy struct info to PoolConfig
        _config.baseToken = _deployConfig.baseToken;
        _config.linkerFactory = _deployConfig.linkerFactory;
        _config.linkerCodeHash = _deployConfig.linkerCodeHash;
        _config.minimumShareReserves = _deployConfig.minimumShareReserves;
        _config.minimumTransactionAmount = _deployConfig
            .minimumTransactionAmount;
        _config.positionDuration = _deployConfig.positionDuration;
        _config.checkpointDuration = _deployConfig.checkpointDuration;
        _config.timeStretch = _deployConfig.timeStretch;
        _config.governance = _deployConfig.governance;
        _config.feeCollector = _deployConfig.feeCollector;
        _config.fees = _deployConfig.fees;

        _config.initialVaultSharePrice = 1e18; // TODO: Make setter

        return (address(new MockHyperdrive(_config)));
    }
}

// HACK: This contract doesn't return anything because MockHyperdrive deploys
// the target contracts in it's constructor.
contract MockHyperdriveTargetDeployer is IHyperdriveTargetDeployer {
    function deploy(
        IHyperdrive.PoolConfig memory,
        bytes memory
    ) external pure override returns (address) {
        return address(0);
    }
}
