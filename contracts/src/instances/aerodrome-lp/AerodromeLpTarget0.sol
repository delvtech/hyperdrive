// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { IGauge } from "aerodrome/interfaces/IGauge.sol";
import { HyperdriveTarget0 } from "../../external/HyperdriveTarget0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { AERODROME_LP_HYPERDRIVE_KIND } from "../../libraries/Constants.sol";
import { AerodromeLpBase } from "./AerodromeLpBase.sol";

/// @author DELV
/// @title AerodromeLpTarget0
/// @notice AerodromeLpHyperdrive's target0 logic contract. This contract contains
///         all of the getters for Hyperdrive as well as some stateful
///         functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract AerodromeLpTarget0 is HyperdriveTarget0, AerodromeLpBase {
    /// @notice Initializes the target0 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param _gauge The Aerodrome Gauge contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController,
        IGauge _gauge
    ) HyperdriveTarget0(_config, __adminController) AerodromeLpBase(_gauge) {}

    /// @notice Returns the instance's kind.
    /// @return The instance's kind.
    function kind() external pure override returns (string memory) {
        _revert(abi.encode(AERODROME_LP_HYPERDRIVE_KIND));
    }

    /// @notice Gets the Aerodrome gauge contract.  This is where Aerodrome LP
    ///         tokens are deposited to collect AERO rewards.
    /// @return The contract address.
    function gauge() external view returns (address) {
        _revert(abi.encode(address(_gauge)));
    }
}
