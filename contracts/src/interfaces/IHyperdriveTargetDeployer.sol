// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdrive } from "./IHyperdrive.sol";

interface IHyperdriveTargetDeployer {
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes memory _extraData
    ) external returns (address);
}
