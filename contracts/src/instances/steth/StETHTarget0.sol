// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveTarget0 } from "../../external/HyperdriveTarget0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { ILido } from "../../interfaces/ILido.sol";
import { StETHBase } from "./StETHBase.sol";

/// @author DELV
/// @title StETHTarget0
/// @notice StETHHyperdrive's target0 logic contract. This contract contains
///         all of the getters for Hyperdrive as well as some stateful
///         functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract StETHTarget0 is HyperdriveTarget0, StETHBase {
    /// @notice Initializes the target0 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _lido The Lido contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        ILido _lido
    ) HyperdriveTarget0(_config) StETHBase(_lido) {}

    /// @notice Returns the Lido contract.
    /// @return lido The Lido contract.
    function lido() external view returns (ILido) {
        _revert(abi.encode(_lido));
    }
}
