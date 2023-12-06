// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "./IHyperdrive.sol";

interface IERC4626HyperdriveDeployer {
    function deploy(
        IHyperdrive.PoolDeployConfig memory _config,
        bytes memory _extraData,
        address target0,
        address target1
    ) external returns (address);
}
