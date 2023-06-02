// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IMultiTokenRead } from "./IMultiTokenRead.sol";
import { IMultiTokenWrite } from "./IMultiTokenWrite.sol";
import { IMultiTokenMetadata } from "./IMultiTokenMetadata.sol";

interface IMultiToken is
    IMultiTokenRead,
    IMultiTokenWrite,
    IMultiTokenMetadata
{}
