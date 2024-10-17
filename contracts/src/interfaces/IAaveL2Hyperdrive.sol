// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "./IHyperdrive.sol";
import { IAaveL2HyperdriveRead } from "./IAaveL2HyperdriveRead.sol";

// prettier-ignore
interface IAaveL2Hyperdrive is
    IHyperdrive,
    IAaveL2HyperdriveRead
{}
