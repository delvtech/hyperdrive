// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

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

    function balanceOf(address account) external view returns (uint256);
}
