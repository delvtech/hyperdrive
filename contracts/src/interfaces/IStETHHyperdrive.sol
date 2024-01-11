// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "./IHyperdrive.sol";
import { IStETHHyperdriveCore } from "./IStETHHyperdriveCore.sol";
import { IStETHHyperdriveRead } from "./IStETHHyperdriveRead.sol";

// prettier-ignore
interface IStETHHyperdrive is
    IHyperdrive,
    IStETHHyperdriveRead,
    IStETHHyperdriveCore
{}
