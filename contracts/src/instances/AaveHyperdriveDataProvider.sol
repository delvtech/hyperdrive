// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { HyperdriveDataProvider } from "../HyperdriveDataProvider.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { Errors } from "../libraries/Errors.sol";
import { IHyperdrive } from "../interfaces/IHyperdrive.sol";

/// @author DELV
/// @title AaveHyperdriveDataProvider
/// @notice The data provider for AaveHyperdrive instances.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract AaveHyperdriveDataProvider is HyperdriveDataProvider {
    using FixedPointMath for uint256;

    // The aave deployment details, the aave pool
    IERC20 internal immutable aToken;
    // The shares created by this pool, starts at one to one with deposits and increases
    uint256 internal totalShares;

    /// @notice Initializes the data provider.
    /// @param _aToken The assets aToken.
    constructor(IERC20 _aToken) {
        aToken = _aToken;
    }

    ///@notice Loads the share price from the yield source.
    ///@return sharePrice The current share price.
    function _pricePerShare()
        internal
        view
        override
        returns (uint256 sharePrice)
    {
        uint256 assets = aToken.balanceOf(address(this));
        sharePrice = totalShares != 0 ? assets.divDown(totalShares) : 0;
        return sharePrice;
    }
}
