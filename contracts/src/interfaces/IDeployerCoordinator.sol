// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "./IHyperdrive.sol";

interface IDeployerCoordinator {
    function deploy(
        IHyperdrive.PoolDeployConfig memory _config,
        bytes memory _extraData
    ) external returns (address);
}
