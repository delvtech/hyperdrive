// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { MockHyperdriveDataProvider } from "contracts/test/MockHyperdrive.sol";

contract MockHyperdriveFactory is HyperdriveFactory {
    constructor(
        FactoryConfig memory _factoryConfig,
        address _linkerFactory,
        bytes32 _linkerCodeHash
    )
        HyperdriveFactory(
            _factoryConfig,
            _linkerFactory,
            _linkerCodeHash
        )
    {}
}
