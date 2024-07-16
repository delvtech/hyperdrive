// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IEverlongAdmin } from "./IEverlongAdmin.sol";
import { IEverlongERC4626 } from "./IEverlongERC4626.sol";
import { IEverlongPositions } from "./IEverlongPositions.sol";

interface IEverlong is IEverlongAdmin, IEverlongERC4626, IEverlongPositions {}
