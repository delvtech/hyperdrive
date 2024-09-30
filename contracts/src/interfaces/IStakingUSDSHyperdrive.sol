// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "./IHyperdrive.sol";

interface IStakingUSDSHyperdrive is IHyperdrive {
    /// @notice Allows anyone to claim the rewards accrued on the staked USDS.
    ///         After this is called, the funds can be swept by the sweep
    ///         collector.
    function claimRewards() external;

    /// @notice Gets the StakingUSDS vault used as this pool's yield source.
    /// @return The StakingUSDS vault.
    function stakingUSDS() external view returns (address);
}
