// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { MockHyperdriveTarget0, MockHyperdriveTarget1 } from "contracts/test/MockHyperdrive.sol";

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

    function deployTarget0(
        IHyperdrive.PoolConfig memory _config,
        bytes32[] memory,
        bytes32,
        address
    ) internal override returns (address) {
        MockHyperdriveTarget0 target0 = new MockHyperdriveTarget0(_config);
        return address(target0);
    }

    function deployTarget1(
        IHyperdrive.PoolConfig memory _config,
        bytes32[] memory,
        bytes32,
        address
    ) internal override returns (address) {
        MockHyperdriveTarget1 target1 = new MockHyperdriveTarget1(_config);
        return address(target1);
    }
}
