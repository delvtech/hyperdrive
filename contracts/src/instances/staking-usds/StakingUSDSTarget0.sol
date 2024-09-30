// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { HyperdriveTarget0 } from "../../external/HyperdriveTarget0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { IStakingUSDS } from "../../interfaces/IStakingUSDS.sol";
import { STAKING_USDS_HYPERDRIVE_KIND } from "../../libraries/Constants.sol";
import { StakingUSDSBase } from "./StakingUSDSBase.sol";

/// @author DELV
/// @title StakingUSDSTarget0
/// @notice StakingUSDSHyperdrive's target0 logic contract. This contract contains
///         all of the getters for Hyperdrive as well as some stateful
///         functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract StakingUSDSTarget0 is HyperdriveTarget0, StakingUSDSBase {
    /// @notice Initializes the target0 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param __stakingUSDS The staking USDS contract that pays out rewards.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController,
        IStakingUSDS __stakingUSDS
    )
        HyperdriveTarget0(_config, __adminController)
        StakingUSDSBase(__stakingUSDS)
    {}

    /// @notice Returns the instance's kind.
    /// @return The instance's kind.
    function kind() external pure override returns (string memory) {
        _revert(abi.encode(STAKING_USDS_HYPERDRIVE_KIND));
    }

    /// @notice Gets the StakingUSDS vault used as this pool's yield source.
    /// @return The StakingUSDS vault.
    function stakingUSDS() external view returns (address) {
        _revert(abi.encode(_stakingUSDS));
    }
}
