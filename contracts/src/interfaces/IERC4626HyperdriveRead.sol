// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC4626 } from "./IERC4626.sol";
import { IHyperdriveRead } from "./IHyperdriveRead.sol";

interface IERC4626HyperdriveRead is IHyperdriveRead {
    function pool() external view returns (IERC4626);

    function isSweepable(address _target) external view returns (bool);
}
