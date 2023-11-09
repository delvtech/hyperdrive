// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { Hyperdrive } from "../external/Hyperdrive.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { IERC4626Hyperdrive } from "../interfaces/IERC4626Hyperdrive.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { ERC4626Base } from "./ERC4626Base.sol";

// TODO: Polish the comments as part of #621.
//
/// @author DELV
/// @title ERC4626Hyperdrive
/// @notice A Hyperdrive instance that uses a ERC4626 vault as the yield source.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626Hyperdrive is Hyperdrive, ERC4626Base {
    using FixedPointMath for uint256;
    using SafeTransferLib for IERC20;

    /// @notice Instantiates Hyperdrive with a ERC4626 vault as the yield source.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _target0 The target0 address.
    /// @param _target1 The target1 address.
    /// @param __pool The ERC4626 compatible yield source.
    /// @param _targets The addresses that can be swept by governance. This
    ///        allows governance to collect rewards derived from incentive
    ///        programs while also preventing edge cases where `sweep` is used
    ///        to access the pool or base tokens.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _target0,
        address _target1,
        IERC4626 __pool,
        address[] memory _targets
    ) Hyperdrive(_config, _target0, _target1) ERC4626Base(__pool) {
        // Ensure that the Hyperdrive pool was configured properly.
        // WARN: 4626 implementations should be checked that if they use an
        // asset with decimals less than 18 that the preview deposit is scale
        // invariant. EG - because this line uses a very large query to load
        // price for USDC if the price per share changes based on size of
        // deposit then this line will read an incorrect and possibly dangerous
        // price.
        if (_config.initialSharePrice != _pricePerShare()) {
            revert IHyperdrive.InvalidInitialSharePrice();
        }
        if (address(_config.baseToken) != _pool.asset()) {
            revert IHyperdrive.InvalidBaseToken();
        }

        // Set immutables and prepare for deposits by setting immutables
        if (!_config.baseToken.approve(address(_pool), type(uint256).max)) {
            revert IHyperdrive.ApprovalFailed();
        }

        // Set the sweep targets. The base and pool tokens can't be set as sweep
        // targets to prevent governance from rugging the pool.
        for (uint256 i = 0; i < _targets.length; i++) {
            address target = _targets[i];
            if (
                address(target) == address(_pool) ||
                address(target) == address(_baseToken)
            ) {
                revert IHyperdrive.UnsupportedToken();
            }
            _isSweepable[target] = true;
        }
    }

    /// @notice Some yield sources [eg Morpho] pay rewards directly to this
    ///         contract but we can't handle distributing them internally so we
    ///         sweep to the fee collector address to then redistribute to users.
    /// @dev WARN: The entire balance of any of the sweep targets can be swept
    ///      by governance. If these sweep targets provide access to the base or
    ///      pool token, then governance has the ability to rug the pool.
    /// @dev WARN: It is unlikely but possible that there is a selector overlap
    ///      with 'transferFrom'. Any integrating contracts should be checked
    ///      for that, as it may result in an unexpected call from this address.
    function sweep(IERC20) external {
        _delegate(target1);
    }
}
