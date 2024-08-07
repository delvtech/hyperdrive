// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IHyperdrive } from "./IHyperdrive.sol";
import { IEzETHHyperdriveRead } from "./IEzETHHyperdriveRead.sol";

// prettier-ignore
interface IEzETHHyperdrive is
    IHyperdrive,
    IEzETHHyperdriveRead
{}
