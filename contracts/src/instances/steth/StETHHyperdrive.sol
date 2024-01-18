// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { Hyperdrive } from "../../external/Hyperdrive.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IERC20 } from "../../interfaces/IERC20.sol";
import { ILido } from "../../interfaces/ILido.sol";
import { StETHBase } from "./StETHBase.sol";

/// @author DELV
/// @title StETHHyperdrive
/// @notice A Hyperdrive instance that uses StETH as the yield source.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract StETHHyperdrive is Hyperdrive, StETHBase {
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Instantiates Hyperdrive with StETH as the yield source.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _target0 The target0 address.
    /// @param _target1 The target1 address.
    /// @param _target2 The target2 address.
    /// @param _target3 The target3 address.
    /// @param _lido The Lido contract.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _target0,
        address _target1,
        address _target2,
        address _target3,
        ILido _lido
    )
        Hyperdrive(_config, _target0, _target1, _target2, _target3)
        StETHBase(_lido)
    {
        // Ensure that the base token address is properly configured.
        if (address(_config.baseToken) != ETH) {
            revert IHyperdrive.InvalidBaseToken();
        }

        // Ensure that the initial vault share price is properly configured.
        if (_config.initialVaultSharePrice != _pricePerVaultShare()) {
            revert IHyperdrive.InvalidInitialVaultSharePrice();
        }
    }

    /// @notice Some yield sources [eg Morpho] pay rewards directly to this
    ///         contract but we can't handle distributing them internally so we
    ///         sweep to the fee collector address to then redistribute to users.
    /// @dev WARN: It is unlikely but possible that there is a selector overlap
    ///      with 'transferFrom'. Any integrating contracts should be checked
    ///      for that, as it may result in an unexpected call from this address.
    function sweep(IERC20) external {
        _delegate(target0);
    }
}
