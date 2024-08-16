// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IMultiTokenCore } from "./IMultiTokenCore.sol";
import { IMultiTokenEvents } from "./IMultiTokenEvents.sol";
import { IMultiTokenMetadata } from "./IMultiTokenMetadata.sol";
import { IMultiTokenRead } from "./IMultiTokenRead.sol";

interface IMultiToken is
    IMultiTokenEvents,
    IMultiTokenRead,
    IMultiTokenCore,
    IMultiTokenMetadata
{}
