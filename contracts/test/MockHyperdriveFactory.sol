// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { MockHyperdriveDataProvider } from "contracts/test/MockHyperdrive.sol";

contract MockHyperdriveFactory is HyperdriveFactory {
    constructor(
        FactoryConfig memory _factoryConfig,
        IHyperdriveDeployer _deployer,
        address _linkerFactory,
        bytes32 _linkerCodeHash
    )
        HyperdriveFactory(
            _factoryConfig,
            _deployer,
            _linkerFactory,
            _linkerCodeHash
        )
    {}

    function deployDataProvider(
        IHyperdrive.PoolConfig memory _config,
        bytes32[] memory,
        bytes32,
        address,
        address
    ) internal override returns (address) {
        MockHyperdriveDataProvider dataProvider = new MockHyperdriveDataProvider(
                _config
            );
        return address(dataProvider);
    }
}
