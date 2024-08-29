// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { HyperdriveTarget0 } from "../../external/HyperdriveTarget0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { IRSETHPoolV2 } from "../../interfaces/IRSETHPoolV2.sol";
import { RSETH_LINEA_HYPERDRIVE_KIND } from "../../libraries/Constants.sol";
import { RsETHLineaBase } from "./RsETHLineaBase.sol";

/// @author DELV
/// @title RsETHLineaTarget0
/// @notice RsETHLineaHyperdrive's target0 logic contract. This contract contains
///         all of the getters for Hyperdrive as well as some stateful
///         functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract RsETHLineaTarget0 is HyperdriveTarget0, RsETHLineaBase {
    /// @notice Initializes the target0 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param __rsETHPool The Kelp DAO deposit contract that provides the
    ///        vault share price.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController,
        IRSETHPoolV2 __rsETHPool
    )
        HyperdriveTarget0(_config, __adminController)
        RsETHLineaBase(__rsETHPool)
    {}

    /// @notice Returns the instance's kind.
    /// @return The instance's kind.
    function kind() external pure override returns (string memory) {
        _revert(abi.encode(RSETH_LINEA_HYPERDRIVE_KIND));
    }

    /// @notice Returns the MultiToken's decimals.
    /// @return The MultiToken's decimals.
    function decimals() external pure override returns (uint8) {
        _revert(abi.encode(uint8(18)));
    }

    /// @notice Gets the Kelp DAO deposit contract on Linea. The rsETH/ETH price
    ///         is used as the vault share price.
    /// @return The Kelp DAO deposit contract on Linea.
    function rsETHPool() external view returns (IRSETHPoolV2) {
        _revert(abi.encode(_rsETHPool));
    }
}
