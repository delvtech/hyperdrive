// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IERC4626HyperdriveRead } from "./IERC4626HyperdriveRead.sol";
import { IHyperdrive } from "./IHyperdrive.sol";

// prettier-ignore
interface IERC4626Hyperdrive is
    IHyperdrive,
    IERC4626HyperdriveRead
{}
