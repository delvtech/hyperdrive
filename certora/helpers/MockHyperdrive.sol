// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IHyperdrive, MockHyperdrive } from "../../test/mocks/MockHyperdrive.sol";
//import { HyperdriveStorageGetters } from "./HyperdriveStorageGetters.sol";

contract MockHyperdriveStorage is MockHyperdrive {
    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _dataProvider
    ) MockHyperdrive(_config, _dataProvider) {}

    function curveFee() public view returns (uint256) {
        return _curveFee;
    }

    function flatFee() public view returns (uint256) {
        return _flatFee;
    }

    function governanceFee() public view returns (uint256) {
        return _governanceFee;
    }
}
