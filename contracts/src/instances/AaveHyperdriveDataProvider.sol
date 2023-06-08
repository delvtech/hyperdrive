// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { IPool } from "@aave/interfaces/IPool.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { HyperdriveDataProvider } from "../HyperdriveDataProvider.sol";
import { MultiTokenDataProvider } from "../MultiTokenDataProvider.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { Errors } from "../libraries/Errors.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";

/// @author DELV
/// @title AaveHyperdriveDataProvider
/// @notice The data provider for AaveHyperdrive instances.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract AaveHyperdriveDataProvider is
    MultiTokenDataProvider,
    HyperdriveDataProvider
{
    using FixedPointMath for uint256;

    // The aave deployment details, the aave pool
    IERC20 internal immutable _aToken;
    IPool internal immutable _pool;

    // The shares created by this pool, starts at one to one with deposits and increases
    uint256 internal _totalShares;

    /// @notice Initializes the data provider.
    /// @param _linkerCodeHash_ The hash of the erc20 linker contract deploy code
    /// @param _factory_ The factory which is used to deploy the linking contracts
    /// @param _aToken_ The assets aToken.
    /// @param _pool_ The aave pool.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        bytes32 _linkerCodeHash_,
        address _factory_,
        IERC20 _aToken_,
        IPool _pool_
    )
        HyperdriveDataProvider(_config)
        MultiTokenDataProvider(_linkerCodeHash_, _factory_)
    {
        _aToken = _aToken_;
        _pool = _pool_;
    }

    /// Yield Source ///

    ///@notice Loads the share price from the yield source.
    ///@return sharePrice The current share price.
    function _pricePerShare()
        internal
        view
        override
        returns (uint256 sharePrice)
    {
        uint256 assets = _aToken.balanceOf(address(this));
        sharePrice = _totalShares != 0 ? assets.divDown(_totalShares) : 0;
        return sharePrice;
    }

    /// Getters ///

    /// @notice Gets the aave aToken.
    /// @return The aave aToken.
    function aToken() external view returns (IERC20) {
        _revert(abi.encode(_aToken));
    }

    /// @notice Gets the aave pool.
    /// @return The aave pool.
    function pool() external view returns (IPool) {
        _revert(abi.encode(_pool));
    }

    /// @notice Gets the total shares.
    /// @return The total shares.
    function totalShares() external view returns (uint256) {
        _revert(abi.encode(_totalShares));
    }
}
