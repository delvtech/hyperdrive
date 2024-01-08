// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "./IHyperdrive.sol";

interface IHyperdriveCoreDeployer {
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes memory _extraData,
        address target0,
        address target1,
        address target2,
        address target3
    ) external returns (address);
}
