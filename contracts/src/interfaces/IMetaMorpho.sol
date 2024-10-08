// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { Id, IMorpho } from "morpho-blue/src/interfaces/IMorpho.sol";
import { IERC4626 } from "./IERC4626.sol";

abstract contract IMetaMorpho is IERC4626 {
    function MORPHO() external view virtual returns (IMorpho);

    function fee() external view virtual returns (uint96);

    function owner() external view virtual returns (address);

    function withdrawQueue(uint256) external view virtual returns (Id);

    function withdrawQueueLength() external view virtual returns (uint256);

    function setFee(uint256) external virtual;
}
