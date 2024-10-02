// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IERC20 } from "./IERC20.sol";

/// @author DELV
/// @title IStakingUSDS
/// @notice The interface file for StakingUSDS
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
interface IStakingUSDS {
    function stake(uint256 amount) external;

    function stake(uint256 amount, uint16 referral) external;

    function withdraw(uint256 amount) external;

    function exit() external;

    function getReward() external;

    function earned(address account) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function rewardsToken() external view returns (IERC20);

    function stakingToken() external view returns (IERC20);
}
