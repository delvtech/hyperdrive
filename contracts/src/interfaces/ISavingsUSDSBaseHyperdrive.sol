// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { IHyperdrive } from "./IHyperdrive.sol";

interface ISavingsUSDSBaseHyperdrive is
    IHyperdrive
{
    /// @notice Gets the vault used as this pool's yield source.
    /// @return The compatible yield source.
    function vault() external view returns (address);
}
