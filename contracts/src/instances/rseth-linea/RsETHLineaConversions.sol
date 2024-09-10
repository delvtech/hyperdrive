// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IRSETHPoolV2 } from "../../interfaces/IRSETHPoolV2.sol";
import { FixedPointMath } from "../../libraries/FixedPointMath.sol";

/// @author DELV
/// @title RsETHLineaConversions
/// @notice The conversion logic for the  RsETHLinea Hyperdrive integration.
/// @dev This conversion library pulls the vault share price from the Kelp DAO
///      oracle on Linea. It's possible for this oracle to have downtime or
///      to be deprecated entirely. Our approach to this problem is to always
///      use the latest price data (regardless of how current it is) since
///      reverting will compromise the protocol's liveness and will prevent
///      users from closing their existing positions. These pools should be
///      monitored to ensure that the underlying oracle continues to be
///      maintained, and the pool should be paused if the oracle has significant
///      downtime or is deprecated.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library RsETHLineaConversions {
    using FixedPointMath for uint256;

    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _rsETHPool The Kelp DAO deposit pool on Linea.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function convertToBase(
        IRSETHPoolV2 _rsETHPool,
        uint256 _shareAmount
    ) internal view returns (uint256) {
        // Get the last rsETH/ETH price. This is our vault share price.
        uint256 price = getPrice(_rsETHPool);

        return _shareAmount.mulDown(price);
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _rsETHPool The Kelp DAO deposit pool on Linea.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function convertToShares(
        IRSETHPoolV2 _rsETHPool,
        uint256 _baseAmount
    ) internal view returns (uint256) {
        // Get the last rsETH/ETH price. This is our vault share price.
        uint256 price = getPrice(_rsETHPool);

        return _baseAmount.divDown(price);
    }

    /// @dev Gets the rsETH/ETH price from the Kelp DAO deposit pool. This is
    ///      the price that we'll use as our vault share price.
    /// @param _rsETHPool The Kelp DAO deposit pool on Linea.
    /// @return The last rsETH/ETH price provided by the oracle.
    function getPrice(IRSETHPoolV2 _rsETHPool) internal view returns (uint256) {
        return _rsETHPool.getRate();
    }
}
