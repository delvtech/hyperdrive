// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;
import { console2 as console } from "forge-std/console2.sol";

import { HyperdriveTarget0 } from "../../external/HyperdriveTarget0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { IMToken } from "../../interfaces/IMoonwell.sol";
import { MOONWELL_HYPERDRIVE_KIND } from "../../libraries/Constants.sol";
import { MoonwellBase } from "./MoonwellBase.sol";

/// @author DELV
/// @title MoonwellTarget0
/// @notice MoonwellHyperdrive's target0 logic contract. This contract contains
///         all of the getters for Hyperdrive as well as some stateful
///         functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract MoonwellTarget0 is HyperdriveTarget0, MoonwellBase {
    /// @notice Initializes the target0 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController
    ) HyperdriveTarget0(_config, __adminController) {}

    /// @notice Returns the instance's kind.
    /// @return The instance's kind.
    function kind() external pure override returns (string memory) {
        _revert(abi.encode(MOONWELL_HYPERDRIVE_KIND));
    }

    // FIXME
    //
    // /// @notice Gets the current exchange rate on the Moonwell vault.
    // /// @return The current exchange rate on the Moonwell vault.
    // function exchangeRateCurrent() external returns (uint256) {
    //     _revert(abi.encode(IMToken(address(_vaultSharesToken))));
    // }
}
