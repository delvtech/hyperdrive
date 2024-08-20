// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { HyperdriveTarget0 } from "../../external/HyperdriveTarget0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { EETH_HYPERDRIVE_KIND } from "../../libraries/Constants.sol";
import { ILiquidityPool } from "../../interfaces/ILiquidityPool.sol";
import { EETHBase } from "./EETHBase.sol";

/// @author DELV
/// @title EETHTarget0
/// @notice EETHHyperdrive's target0 logic contract. This contract contains
///         all of the getters for Hyperdrive as well as some stateful
///         functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract EETHTarget0 is HyperdriveTarget0, EETHBase {
    /// @notice Initializes the target0 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param _liquidityPool The Etherfi liquidity pool contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController,
        ILiquidityPool _liquidityPool
    ) HyperdriveTarget0(_config, __adminController) EETHBase(_liquidityPool) {}

    /// @inheritdoc HyperdriveTarget0
    function kind() external pure override returns (string memory) {
        _revert(abi.encode(EETH_HYPERDRIVE_KIND));
    }

    /// @notice Returns the Etherfi liquidity pool contract.
    /// @return The Etherfi liquidity pool contract.
    function liquidityPool() external view returns (ILiquidityPool) {
        _revert(abi.encode(_liquidityPool));
    }

    /// @inheritdoc HyperdriveTarget0
    function decimals() external pure override returns (uint8) {
        _revert(abi.encode(uint8(18)));
    }
}
