// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdrive } from "./IHyperdrive.sol";
import { IEzETHHyperdriveCore } from "./IEzETHHyperdriveCore.sol";
import { IEzETHHyperdriveRead } from "./IEzETHHyperdriveRead.sol";

// prettier-ignore
interface IEzETHHyperdrive is
    IHyperdrive,
    IEzETHHyperdriveRead,
    IEzETHHyperdriveCore
{}
