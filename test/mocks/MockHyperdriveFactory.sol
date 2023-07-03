// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { MockHyperdriveDataProvider } from "test/mocks/MockHyperdrive.sol";

contract MockHyperdriveFactory is HyperdriveFactory {
    constructor(
        address _governance,
        IHyperdriveDeployer _deployer,
        address _hyperdriveGovernance,
        address _feeCollector,
        IHyperdrive.Fees memory _fees,
        IHyperdrive.Fees memory _maxFees,
        address[] memory _defaultPausers,
        address _linkerFactory,
        bytes32 _linkerCodeHash
    )
        HyperdriveFactory(
            _governance,
            _deployer,
            _hyperdriveGovernance,
            _feeCollector,
            _fees,
            _maxFees,
            _defaultPausers,
            _linkerFactory,
            _linkerCodeHash
        )
    {}

    function deployDataProvider(
        IHyperdrive.PoolConfig memory _config,
        bytes32[] memory,
        bytes32,
        address
    ) internal override returns (address) {
        MockHyperdriveDataProvider dataProvider = new MockHyperdriveDataProvider(
                _config
            );
        return address(dataProvider);
    }
}
