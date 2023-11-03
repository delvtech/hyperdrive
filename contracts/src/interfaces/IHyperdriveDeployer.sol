// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC20 } from "./IERC20.sol";
import { IHyperdrive } from "./IHyperdrive.sol";

interface IHyperdriveDeployer {
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        address _extras,
        address _dataProvider,
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        bytes32[] memory _extraData
    ) external returns (address);
}
