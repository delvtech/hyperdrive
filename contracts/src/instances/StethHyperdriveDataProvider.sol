// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { HyperdriveDataProvider } from "../HyperdriveDataProvider.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { ILido } from "../interfaces/ILido.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { MultiTokenDataProvider } from "../token/MultiTokenDataProvider.sol";

/// @author DELV
/// @title StethHyperdriveDataProvider
/// @notice The data provider for StethHyperdrive instances.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract StethHyperdriveDataProvider is
    MultiTokenDataProvider,
    HyperdriveDataProvider
{
    using FixedPointMath for uint256;

    /// @dev The Lido contract.
    ILido internal immutable _lido;

    /// @notice Initializes the data provider.
    /// @param _config The configuration of the Hyperdrive pool.
    /// @param _linkerCodeHash_ The hash of the erc20 linker contract deploy code.
    /// @param _factory_ The factory which is used to deploy the linking contracts.
    /// @param _lido_ The Lido contract. This is the stETH token.
    constructor(
        IHyperdrive.PoolConfig memory _config,
        bytes32 _linkerCodeHash_,
        address _factory_,
        ILido _lido_
    )
        HyperdriveDataProvider(_config)
        MultiTokenDataProvider(_linkerCodeHash_, _factory_)
    {
        _lido = _lido_;
    }

    /// Yield Source ///

    /// @dev Returns the current share price. We simply use Lido's share price.
    /// @return price The current share price.
    /// @dev must remain consistent with the impl inside of the HyperdriveInstance
    function _pricePerShare() internal view override returns (uint256 price) {
        return _lido.getTotalPooledEther().divDown(_lido.getTotalShares());
    }

    /// Getters ///

    /// @notice Gets the Lido contract.
    /// @return The Lido contract.
    function lido() external view returns (ILido) {
        _revert(abi.encode(_lido));
    }
}
