// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { HyperdriveTarget4 } from "../../external/HyperdriveTarget4.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { IStakingUSDS } from "../../interfaces/IStakingUSDS.sol";
import { StakingUSDSBase } from "./StakingUSDSBase.sol";

/// @author DELV
/// @title StakingUSDSTarget4
/// @notice StakingUSDSHyperdrive's target4 logic contract. This contract contains
///         several stateful functions that couldn't fit into the Hyperdrive
///         contract.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract StakingUSDSTarget4 is HyperdriveTarget4, StakingUSDSBase {
    /// @notice Initializes the target4 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param __stakingUSDS The staking USDS contract that pays out rewards.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController,
        IStakingUSDS __stakingUSDS
    )
        HyperdriveTarget4(_config, __adminController)
        StakingUSDSBase(__stakingUSDS)
    {}
}
