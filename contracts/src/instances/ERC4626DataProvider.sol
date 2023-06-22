// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IERC4626 } from "../interfaces/IERC4626.sol";
import { HyperdriveDataProvider } from "../HyperdriveDataProvider.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { Errors } from "../libraries/Errors.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { MultiTokenDataProvider } from "../token/MultiTokenDataProvider.sol";

/// @author DELV
/// @title ERC4626DataProvider
/// @notice The data provider for ERC4626Hyperdrive instances.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract ERC4626DataProvider is MultiTokenDataProvider, HyperdriveDataProvider {
    using FixedPointMath for uint256;

    // The deployed pool
    IERC4626 internal immutable _pool;

    /// @notice Initializes the data provider.
    /// @param _linkerCodeHash_ The hash of the erc20 linker contract deploy code
    /// @param _factory_ The factory which is used to deploy the linking contracts
    /// @param _pool_ The ERC4626 pool.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        bytes32 _linkerCodeHash_,
        address _factory_,
        IERC4626 _pool_
    )
        HyperdriveDataProvider(_config)
        MultiTokenDataProvider(_linkerCodeHash_, _factory_)
    {
        _pool = _pool_;
    }

    /// Yield Source ///

    /// @notice Loads the share price from the yield source.
    /// @return sharePrice The current share price.
    /// @dev must remain consistent with the impl inside of the HyperdriveInstance
    function _pricePerShare()
        internal
        view
        override
        returns (uint256 sharePrice)
    {
        uint256 shareEstimate = _pool.convertToShares(FixedPointMath.ONE_18);
        sharePrice = shareEstimate.divDown(FixedPointMath.ONE_18);
        return (sharePrice);
    }

    /// Getters ///

    /// @notice Gets the 4626 pool.
    /// @return The 4626 pool.
    function pool() external view returns (IERC4626) {
        _revert(abi.encode(_pool));
    }
}
