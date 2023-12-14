// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "./IHyperdrive.sol";

interface IHyperdriveTargetDeployer {
    function deploy(
        IHyperdrive.PoolDeployConfig memory _config,
        uint256 initialSharePrice,
        bytes memory _extraData
    ) external returns (address);
}
