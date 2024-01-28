// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IERC20 } from "./IERC20.sol";
import { IHyperdriveCore } from "./IHyperdriveCore.sol";

interface IERC4626HyperdriveCore is IHyperdriveCore {
    function sweep(IERC20 _target) external;
}
