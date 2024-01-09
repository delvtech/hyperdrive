// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IHyperdrive } from "./IHyperdrive.sol";
import { IStETHHyperdriveRead } from "./IStETHHyperdriveRead.sol";

// prettier-ignore
interface IStETH6Hyperdrive is
    IHyperdrive,
    IStETHHyperdriveRead
{}
