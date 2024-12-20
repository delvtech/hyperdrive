// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { HyperdriveTarget0 } from "../../external/HyperdriveTarget0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { SAVINGS_USDS_L2_HYPERDRIVE_KIND } from "../../libraries/Constants.sol";
import { SavingsUSDSL2Base } from "./SavingsUSDSL2Base.sol";
import { IPSM } from "../../interfaces/IPSM.sol";

/// @author DELV
/// @title SavingsUSDSL2Target0
/// @notice SavingsUSDSL2Hyperdrive's target0 logic contract. This contract contains
///         all of the getters for Hyperdrive as well as some stateful
///         functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract SavingsUSDSL2Target0 is HyperdriveTarget0, SavingsUSDSL2Base {
    /// @notice Initializes the target0 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param _PSM the PSM contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController,
        IPSM _PSM
    ) HyperdriveTarget0(_config, __adminController) SavingsUSDSL2Base(_PSM) {}

    /// @notice Returns the instance's kind.
    /// @return The instance's kind.
    function kind() external pure override returns (string memory) {
        _revert(abi.encode(SAVINGS_USDS_L2_HYPERDRIVE_KIND));
    }

    /// @notice Gets the PSM contract.  This is where USDS is swapped for
    ///         SUSDS.
    /// @return The contract address.
    function psm() external view returns (address) {
        _revert(abi.encode(address(_PSM)));
    }
}
