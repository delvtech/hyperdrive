// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC20 } from "./IERC20.sol";
import { IERC4626 } from "./IERC4626.sol";
import { IHyperdrive } from "./IHyperdrive.sol";

interface IERC4626Hyperdrive is IHyperdrive {
    function sweep(IERC20 _target) external;

    function pool() external view returns (IERC4626);

    function isSweepable(address _target) external view returns (bool);
}
