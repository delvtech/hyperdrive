// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IHyperdrive } from "./IHyperdrive.sol";
import { IMultiTokenRead } from "./IMultiTokenRead.sol";

interface IHyperdriveRead is IMultiTokenRead {
    /// @notice Gets the instance's name.
    /// @return The instance's name.
    function name() external view returns (string memory);

    /// @notice Gets the instance's kind.
    /// @return The instance's kind.
    function kind() external pure returns (string memory);

    /// @notice Gets the instance's version.
    /// @return The instance's version.
    function version() external pure returns (string memory);

    /// @notice Gets the address that contains the admin configuration for this
    ///         instance.
    /// @return The admin controller address.
    function adminController() external view returns (address);

    /// @notice Gets the Hyperdrive pool's base token.
    /// @return The base token.
    function baseToken() external view returns (address);

    /// @notice Gets the Hyperdrive pool's vault shares token.
    /// @return The vault shares token.
    function vaultSharesToken() external view returns (address);

    /// @notice Gets one of the pool's checkpoints.
    /// @param _checkpointTime The checkpoint time.
    /// @return The checkpoint.
    function getCheckpoint(
        uint256 _checkpointTime
    ) external view returns (IHyperdrive.Checkpoint memory);

    /// @notice Gets the pool's exposure from a checkpoint. This is the number
    ///         of non-netted longs in the checkpoint.
    /// @param _checkpointTime The checkpoint time.
    /// @return The checkpoint exposure.
    function getCheckpointExposure(
        uint256 _checkpointTime
    ) external view returns (int256);

    /// @notice Gets the pool's state relating to the Hyperdrive market.
    /// @return The market state.
    function getMarketState()
        external
        view
        returns (IHyperdrive.MarketState memory);

    /// @notice Gets the pool's configuration parameters.
    /// @return The pool configuration.
    function getPoolConfig()
        external
        view
        returns (IHyperdrive.PoolConfig memory);

    /// @notice Gets info about the pool's reserves and other state that is
    ///         important to evaluate potential trades.
    /// @return The pool info.
    function getPoolInfo() external view returns (IHyperdrive.PoolInfo memory);

    /// @notice Gets the amount of governance fees that haven't been collected.
    /// @return The amount of uncollected governance fees.
    function getUncollectedGovernanceFees() external view returns (uint256);

    /// @notice Gets information relating to the pool's withdrawal pool. This
    ///         includes the total proceeds underlying the withdrawal pool and
    ///         the number of withdrawal shares ready to be redeemed.
    /// @return The withdrawal pool information.
    function getWithdrawPool()
        external
        view
        returns (IHyperdrive.WithdrawPool memory);

    /// @notice Gets an account's pauser status within the Hyperdrive pool.
    /// @param _account The account to check.
    /// @return The account's pauser status.
    function isPauser(address _account) external view returns (bool);

    /// @notice Gets the storage values at the specified slots.
    /// @dev This serves as a generalized getter that allows consumers to create
    ///      custom getters to suit their purposes.
    /// @param _slots The storage slots to load.
    /// @return The values at the specified slots.
    function load(
        uint256[] calldata _slots
    ) external view returns (bytes32[] memory);

    /// @notice Convert an amount of vault shares to an amount of base.
    /// @dev This is a convenience method that allows developers to convert from
    ///      vault shares to base without knowing the specifics of the
    ///      integration.
    /// @param _shareAmount The vault shares amount.
    /// @return baseAmount The base amount.
    function convertToBase(
        uint256 _shareAmount
    ) external view returns (uint256);

    /// @notice Convert an amount of base to an amount of vault shares.
    /// @dev This is a convenience method that allows developers to convert from
    ///      base to vault shares without knowing the specifics of the
    ///      integration.
    /// @param _baseAmount The base amount.
    /// @return shareAmount The vault shares amount.
    function convertToShares(
        uint256 _baseAmount
    ) external view returns (uint256);

    /// @notice Gets the total amount of vault shares held by Hyperdrive.
    /// @dev This is a convenience method that allows developers to get the
    ///      total amount of vault shares without knowing the specifics of the
    ///      integration.
    /// @return The total amount of vault shares held by Hyperdrive.
    function totalShares() external view returns (uint256);
}
