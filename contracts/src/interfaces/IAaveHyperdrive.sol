// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IHyperdrive } from "./IHyperdrive.sol";
import { IAaveHyperdriveRead } from "./IAaveHyperdriveRead.sol";

// prettier-ignore
interface IAaveHyperdrive is
    IHyperdrive,
    IAaveHyperdriveRead
{}
