// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "./IHyperdrive.sol";

interface IHyperdriveDeployer {
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        address _target0,
        address _target1,
        bytes32[] memory _extraData
    ) external returns (address);
}
