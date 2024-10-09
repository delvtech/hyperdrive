// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IERC20 } from "./IERC20.sol";

interface IStakedToken is IERC20 {
    function STAKED_TOKEN() external view returns (IERC20);

    function REWARD_TOKEN() external view returns (IERC20);

    function stakerRewardsToClaim(address) external view returns (uint256);

    function stake(address to, uint256 amount) external;

    function claimRewards(address to, uint256 amount) external;
}
