// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { ERC20 } from "openzeppelin/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { Hyperdrive } from "../../external/Hyperdrive.sol";
import { IERC20 } from "../../interfaces/IERC20.sol";
import { IERC4626 } from "../../interfaces/IERC4626.sol";
import { IHyperdrive } from "../../interfaces/IHyperdrive.sol";
import { IERC4626Hyperdrive } from "../../interfaces/IERC4626Hyperdrive.sol";
import { FixedPointMath } from "../../libraries/FixedPointMath.sol";
import { ERC4626Base } from "./ERC4626Base.sol";

/// @author DELV
/// @title ERC4626Hyperdrive
/// @notice A Hyperdrive instance that uses a ERC4626 vault as the yield source.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626Hyperdrive is Hyperdrive, ERC4626Base {
    using FixedPointMath for uint256;
    using SafeERC20 for ERC20;

    /// @notice Instantiates Hyperdrive with a ERC4626 vault as the yield source.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _target0 The target0 address.
    /// @param _target1 The target1 address.
    /// @param _target2 The target2 address.
    /// @param _target3 The target3 address.
    /// @param __vault The ERC4626 compatible yield source.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        address _target0,
        address _target1,
        address _target2,
        address _target3,
        IERC4626 __vault
    )
        Hyperdrive(_config, _target0, _target1, _target2, _target3)
        ERC4626Base(__vault)
    {
        // Ensure that the base token is the same as the vault's underlying
        // asset.
        if (address(_config.baseToken) != IERC4626(_vault).asset()) {
            revert IHyperdrive.InvalidBaseToken();
        }

        // Approve the base token with 1 wei. This ensures that all of the
        // subsequent approvals will be writing to a dirty storage slot.
        ERC20(address(_config.baseToken)).forceApprove(address(_vault), 1);
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
