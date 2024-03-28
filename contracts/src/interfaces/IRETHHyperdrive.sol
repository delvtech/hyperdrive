// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdrive } from "./IHyperdrive.sol";
import { IRETHHyperdriveRead } from "./IRETHHyperdriveRead.sol";

interface IRETHHyperdrive is IHyperdrive, IRETHHyperdriveRead {}
