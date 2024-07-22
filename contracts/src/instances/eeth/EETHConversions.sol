// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { ILiquidityPool } from ".etherfi/src/interfaces/ILendingPool.sol";
import { IeETH } from ".etherfi/src/interfaces/IeETH.sol";

/// @author DELV
/// @title EETHConversions
/// @notice The conversion logic for the EETH integration.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library EETHConversions {
    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _liquidityPool The Etherfi liquidity pool contract.
    /// @param _eETH The eETH contract.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function convertToBase(
        ILiquidityPool _liquidityPool,
        IeETH _eETH,
        uint256 _shareAmount
    ) internal view returns (uint256) {
        uint256 totalShares = eETH.totalShares();
        if (totalShares == 0) {
            return 0;
        }

        // This calculation matches the implementation of 
        // `amountForShare(uint256 _share)` found in the LiquidityPool
        //  contract.
        // NOTE: Round down so that the output is an underestimate.
        return _share.mulDown(_liquidityPool.getTotalPooledEther())
                     .divDown(totalShares);
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _liquidityPool The Etherfi liquidity pool contract.
    /// @param _eETH The eETH contract.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function convertToShares(
        ILiquidityPool _liquidityPool,
        IeETH _eETH,
        uint256 _baseAmount
    ) internal view returns (uint256) {
        uint256 totalPooledEther = _liquidityPool.getTotalPooledEther();
        if (totalPooledEther == 0) {
            return 0;
        }

        // This calculation matches the implementation of
        // `sharesForAmount(uint256 _amount)` found in the LiquidityPool
        // contract.
        // NOTE: Round down so that the output is an underestimate.
        return _baseAmount.mulDown(_eETH.totalShares())
                          .divDown(totalPooledEther);
    }
}
