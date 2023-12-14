// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { IHyperdriveTargetDeployer } from "contracts/src/interfaces/IHyperdriveTargetDeployer.sol";
import { MockHyperdrive } from "./MockHyperdrive.sol";

contract MockHyperdriveDeployer is IHyperdriveDeployer {
    function deploy(
        IHyperdrive.PoolDeployConfig memory _config,
        bytes memory
    ) external override returns (address) {
        return (address(new MockHyperdrive(_config, 1e18)));
    }
}

// HACK: This contract doesn't return anything because MockHyperdrive deploys
// the target contracts in it's constructor.
contract MockHyperdriveTargetDeployer is IHyperdriveTargetDeployer {
    function deploy(
        IHyperdrive.PoolDeployConfig memory,
        uint256,
        bytes memory
    ) external pure override returns (address) {
        return address(0);
    }
}
