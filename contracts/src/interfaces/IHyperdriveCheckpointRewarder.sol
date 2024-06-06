// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

interface IHyperdriveCheckpointRewarder {
    /// @notice Claims a checkpoint reward.
    /// @param _claimant The address that is claiming the checkpoint reward.
    /// @param _checkpointTime The time of the checkpoint that was minted.
    /// @param _isTrader A boolean indicating whether or not the checkpoint was
    ///        minted by a trader or by someone calling checkpoint directly.
    function claimCheckpointReward(
        address _claimant,
        uint256 _checkpointTime,
        bool _wasTrader
    ) external;
}
