// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { IHyperdriveTargetDeployer } from "contracts/src/interfaces/IHyperdriveTargetDeployer.sol";
import { MockHyperdrive, MockHyperdriveTarget0, MockHyperdriveTarget1 } from "./MockHyperdrive.sol";

contract MockHyperdriveDeployer is IHyperdriveDeployer {
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        address _target0,
        address _target1,
        bytes32,
        address,
        bytes32[] memory
    ) external override returns (address) {
        return (address(new MockHyperdrive(_config, _target0, _target1)));
    }
}

contract MockHyperdriveTarget0Deployer is IHyperdriveTargetDeployer {
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes32,
        address,
        bytes32[] memory
    ) external override returns (address) {
        return address(new MockHyperdriveTarget0(_config));
    }
}

contract MockHyperdriveTarget1Deployer is IHyperdriveTargetDeployer {
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes32,
        address,
        bytes32[] memory
    ) external override returns (address) {
        return address(new MockHyperdriveTarget1(_config));
    }
}
