// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IPool } from "aave/interfaces/IPool.sol";
import { IL2Pool as IL2PoolAave } from "aave/interfaces/IL2Pool.sol";

interface IL2Pool is IPool, IL2PoolAave {}
