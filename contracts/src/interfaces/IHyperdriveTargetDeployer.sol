// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "./IHyperdrive.sol";

interface IHyperdriveTargetDeployer {
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes memory _extraData,
        // TODO: Remove this from the interface.
        address _pool
    ) external returns (address);
}
