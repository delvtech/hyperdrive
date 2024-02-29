// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdrive } from "./IHyperdrive.sol";
import { IezETHHyperdriveCore } from "./IezETHHyperdriveCore.sol";
import { IezETHHyperdriveRead } from "./IezETHHyperdriveRead.sol";

// prettier-ignore
interface IezETHHyperdrive is
    IHyperdrive,
    IezETHHyperdriveRead,
    IezETHHyperdriveCore
{}
