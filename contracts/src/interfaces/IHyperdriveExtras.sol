// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "./IHyperdrive.sol";

interface IHyperdriveExtras {
    function collectGovernanceFee(
        IHyperdrive.Options calldata _options
    ) external returns (uint256 proceeds);

    function pause(bool _status) external;

    function setPauser(address who, bool status) external;

    function setGovernance(address _who) external;
}
