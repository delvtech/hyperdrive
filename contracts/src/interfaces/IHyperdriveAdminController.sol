// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

interface IHyperdriveAdminController {
    /// @notice Returns the Hyperdrive governance address.
    /// @return The Hyperdrive governance address.
    function hyperdriveGovernance() external view returns (address);

    /// @notice Returns the fee collector that is the target of fee collections.
    /// @return The fee collector.
    function feeCollector() external view returns (address);

    /// @notice Returns the sweep collector that can sweep stuck tokens from
    ///         Hyperdrive instances.
    /// @return The sweep collector.
    function sweepCollector() external view returns (address);

    /// @notice Returns the checkpoint rewarder that can pay out rewards to
    ///         checkpoint minters.
    /// @return The checkpoint rewarder.
    function checkpointRewarder() external view returns (address);

    // TODO: A better interface would be `isPauser`, but this can't be changed
    //       without swapping out the factory.
    //
    /// @notice Returns the checkpoint rewarder that can pay out rewards to
    ///         checkpoint minters.
    /// @return The checkpoint rewarder.
    function defaultPausers() external view returns (address[] memory);
}
