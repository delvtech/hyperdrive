// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdriveRead } from "./IHyperdriveRead.sol";
import { IRocketStorage } from "./IRocketStorage.sol";
import { IRocketTokenRETH } from "./IRocketTokenRETH.sol";

interface IRETHHyperdriveRead is IHyperdriveRead {
    /// @notice Gets the Rocket Storage contract.
    /// @return The Rocket Storage contract.
    function rocketStorage() external view returns (IRocketStorage);

    /// @notice Gets the Rocket Token rETH contract.
    /// @return The Rocket Token rETH contract.
    function rocketTokenRETH() external view returns (IRocketTokenRETH);
}
