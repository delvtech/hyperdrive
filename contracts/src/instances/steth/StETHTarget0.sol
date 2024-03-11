// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { HyperdriveTarget0 } from "../../external/HyperdriveTarget0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IERC20 } from "../../interfaces/IERC20.sol";
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
    using SafeERC20 for ERC20;

    /// @notice Initializes the target0 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __lido The Lido contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        ILido __lido
    ) HyperdriveTarget0(_config) StETHBase(__lido) {}

    /// Getters ///

    /// @notice Returns the Lido contract.
    /// @return lido The Lido contract.
    function lido() external view returns (ILido) {
        _revert(abi.encode(_lido));
    }

    /// @notice Returns the MultiToken's decimals.
    /// @return The MultiToken's decimals.
    function decimals() external pure override returns (uint8) {
        _revert(abi.encode(uint8(18)));
    }
}
