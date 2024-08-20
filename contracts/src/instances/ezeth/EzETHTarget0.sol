// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { HyperdriveTarget0 } from "../../external/HyperdriveTarget0.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../interfaces/IHyperdriveAdminController.sol";
import { IRestakeManager, IRenzoOracle } from "../../interfaces/IRenzo.sol";
import { EZETH_HYPERDRIVE_KIND } from "../../libraries/Constants.sol";
import { EzETHBase } from "./EzETHBase.sol";

/// @author DELV
/// @title EzETHTarget0
/// @notice EzETHHyperdrive's target0 logic contract. This contract contains
///         all of the getters for Hyperdrive as well as some stateful
///         functions.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract EzETHTarget0 is HyperdriveTarget0, EzETHBase {
    using SafeERC20 for ERC20;

    /// @notice Initializes the target0 contract.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param __adminController The admin controller that will specify the
    ///        admin parameters for this instance.
    /// @param _restakeManager The Renzo contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        IHyperdriveAdminController __adminController,
        IRestakeManager _restakeManager
    )
        HyperdriveTarget0(_config, __adminController)
        EzETHBase(_restakeManager)
    {}

    /// Extras ///

    /// @notice Returns the instance's kind.
    /// @return The instance's kind.
    function kind() external pure override returns (string memory) {
        _revert(abi.encode(EZETH_HYPERDRIVE_KIND));
    }

    /// @notice Returns the Renzo contract.
    /// @return The Renzo contract.
    function renzo() external view returns (IRestakeManager) {
        _revert(abi.encode(_restakeManager));
    }

    /// @notice Returns the RenzoOracle contract.
    /// @return The RenzoOracle contract.
    function renzoOracle() external view returns (IRenzoOracle) {
        _revert(abi.encode(_renzoOracle));
    }

    /// @notice Returns the MultiToken's decimals.
    /// @return The MultiToken's decimals.
    function decimals() external pure override returns (uint8) {
        _revert(abi.encode(uint8(18)));
    }
}
