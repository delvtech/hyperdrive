// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IMultiTokenRead } from "./IMultiTokenRead.sol";
import { IMultiTokenWrite } from "./IMultiTokenWrite.sol";

interface IMultiToken is IMultiTokenRead, IMultiTokenWrite { }
