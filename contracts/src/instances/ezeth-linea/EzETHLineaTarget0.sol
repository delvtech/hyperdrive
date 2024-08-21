// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { HyperdriveTarget0 } from "../../external/HyperdriveTarget0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IXRenzoDeposit } from "../../interfaces/IXRenzoDeposit.sol";
import { EZETH_LINEA_HYPERDRIVE_KIND } from "../../libraries/Constants.sol";
import { EzETHLineaBase } from "./EzETHLineaBase.sol";

/// @author DELV
/// @title EzETHLineaTarget0
/// @notice EzETHLineaHyperdrive's target0 logic contract. This contract contains
///         all of the getters for Hyperdrive as well as some stateful
///         functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract EzETHLineaTarget0 is HyperdriveTarget0, EzETHLineaBase {
    /// @notice Initializes the target0 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    constructor(
        IHyperdrive.PoolConfig memory _config
    ) HyperdriveTarget0(_config) {}

    /// @notice Returns the instance's kind.
    /// @return The instance's kind.
    function kind() external pure override returns (string memory) {
        _revert(abi.encode(EZETH_LINEA_HYPERDRIVE_KIND));
    }

    /// @notice Returns the instance's xRenzoDeposit contract. This is the
    ///         contract that provides the vault share price.
    /// @return The instance's xRenzoDeposit contract.
    function xRenzoDeposit() external view returns (IXRenzoDeposit) {
        _revert(abi.encode(_xRenzoDeposit));
    }
}
