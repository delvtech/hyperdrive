// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IHyperdrive } from "./interfaces/IHyperdrive.sol";
import { MultiTokenStorage } from "./MultiTokenStorage.sol";

/// @author DELV
/// @title HyperdriveStorage
/// @notice The storage contract of the Hyperdrive inheritance hierarchy.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
abstract contract HyperdriveStorage is MultiTokenStorage {
    /// Market State ///

    /// @notice The state of the market. This includes the reserves, buffers,
    ///         and other data used to price trades and maintain solvency.
    IHyperdrive.MarketState internal marketState;

    /// @notice The state corresponding to the withdraw pool.
    IHyperdrive.WithdrawPool internal withdrawPool;

    // TODO: Shouldn't these be immutable?
    //
    /// @notice The fee percentages to be applied to trades.
    IHyperdrive.Fees internal fees;

    /// @notice Hyperdrive positions are bucketed into checkpoints, which
    ///         allows us to avoid poking in any period that has LP or trading
    ///         activity. The checkpoints contain the starting share price from
    ///         the checkpoint as well as aggregate volume values.
    mapping(uint256 => IHyperdrive.Checkpoint) internal checkpoints;

    /// @notice Addresses approved in this mapping can pause all deposits into
    ///         the contract and other non essential functionality.
    mapping(address => bool) internal pausers;

    // TODO: This shouldn't be public.
    //
    // Governance fees that haven't been collected yet denominated in shares.
    uint256 internal governanceFeesAccrued;

    // TODO: This shouldn't be public.
    //
    // TODO: Should this be immutable?
    //
    // The address that receives governance fees.
    address internal governance;
}
