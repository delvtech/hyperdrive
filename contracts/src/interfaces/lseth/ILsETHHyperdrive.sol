// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdrive } from "../IHyperdrive.sol";
import { ILsETHHyperdriveRead } from "./ILsETHHyperdriveRead.sol";

interface ILsETHHyperdrive is IHyperdrive, ILsETHHyperdriveRead {}
