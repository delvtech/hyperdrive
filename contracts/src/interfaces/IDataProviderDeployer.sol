// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "./IHyperdrive.sol";

interface IDataProviderDeployer {
    function deploy(
        IHyperdrive.PoolConfig memory _config,
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        bytes memory _extraData
    ) external returns (address);
}
