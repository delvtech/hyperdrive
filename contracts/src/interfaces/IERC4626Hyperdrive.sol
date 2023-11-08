// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC4626HyperdriveCore } from "./IERC4626HyperdriveCore.sol";
import { IERC4626HyperdriveRead } from "./IERC4626HyperdriveRead.sol";

interface IERC4626Hyperdrive is
    IERC4626HyperdriveRead,
    IERC4626HyperdriveCore
{}
