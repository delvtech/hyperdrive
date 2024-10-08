// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "./IHyperdrive.sol";

interface IStkWellHyperdrive is IHyperdrive {
    /// @notice Allows anyone to claim the Well rewards accrued by this contract.
    ///         These rewards will need to be swept by the sweep collector to be
    ///         distributed.
    function claimRewards() external;
}
