// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "../instances/AaveHyperdrive.sol";
import "../interfaces/IHyperdrive.sol";
import "../interfaces/IHyperdriveDeployer.sol";
import { IPool } from "@aave/interfaces/IPool.sol";

interface IAToken {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}

/// @author DELV
/// @title AaveHyperdriveDeployer
/// @notice This is a minimal factory which contains only the logic to deploy
///         hyperdrive and is called by a more complex factory which
///         initializes the Hyperdrive instances and acts as a registry.
/// @dev We use two contracts to avoid any code size limit issues with Hyperdrive.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract AaveHyperdriveDeployer is IHyperdriveDeployer {
    IPool immutable pool;

    constructor(IPool _pool) {
        pool = _pool;
    }

    /// @notice Deploys a copy of hyperdrive with the given params.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _linkerCodeHash The hash of the ERC20 linker contract's
    ///        constructor code.
    /// @param _linkerFactory The address of the factory which is used to deploy
    ///        the ERC20 linker contracts.
    /// FIXME: We should ensure that the aToken address is a valid aToken.
    /// @param _extraData This extra data contains the address of the aToken.
    function deploy(
        IHyperdrive.HyperdriveConfig memory _config,
        bytes32 _linkerCodeHash,
        address _linkerFactory,
        bytes32[] calldata _extraData
    ) external override returns (address) {
        // We force convert
        IERC20 aToken = IERC20(address(uint160(uint256(_extraData[0]))));
        // Need a hard convert cause no direct bytes32 -> address
        return (
            address(
                new AaveHyperdrive(
                    _config,
                    _linkerCodeHash,
                    _linkerFactory,
                    aToken,
                    pool
                )
            )
        );
    }
}
