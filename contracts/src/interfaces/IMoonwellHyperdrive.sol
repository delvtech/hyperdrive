// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IHyperdrive } from "./IHyperdrive.sol";

interface IMoonwellHyperdrive is IHyperdrive {
    // FIXME
    //
    /// @notice Gets the current exchange rate on the Moonwell vault.
    /// @return The current exchange rate on the Moonwell vault.
    function exchangeRateCurrent() external view returns (uint256);
}
