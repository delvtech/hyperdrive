// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "./IHyperdrive.sol";

interface IAerodromeLpHyperdrive is IHyperdrive {
    /// @notice Gets the Aerodrome gauge contract.  This is where Aerodrome LP
    ///         tokens are deposited to collect AERO rewards.
    /// @return The compatible yield source.
    function gauge() external view returns (address);

    /// @notice Gets the amount of AERO rewards that have been collected by the
    ///         pool.
    /// @return The amount of AERO rewards collected.
    function getReward() external view returns (uint256);
}
