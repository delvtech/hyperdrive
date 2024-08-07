// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IERC20 } from "../../interfaces/IERC20.sol";
import { ILiquidityPool } from "../../interfaces/ILiquidityPool.sol";
import { FixedPointMath } from "../../libraries/FixedPointMath.sol";
import { IEETH } from "../../interfaces/IEETH.sol";

/// @author DELV
/// @title EETHConversions
/// @notice The conversion logic for the EETH integration.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library EETHConversions {
    using FixedPointMath for uint256;

    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _liquidityPool The Etherfi liquidity pool contract.
    /// @param _eETH The eETH contract.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function convertToBase(
        ILiquidityPool _liquidityPool,
        IERC20 _eETH,
        uint256 _shareAmount
    ) internal view returns (uint256) {
        // Get the total supply assets and shares after interest accrues.
        uint256 totalShares = IEETH(address(_eETH)).totalShares();
        if (totalShares == 0) {
            return 0;
        }

        // This calculation matches the implementation of
        // `amountForShare(uint256 _share)` found in the LiquidityPool
        //  contract.
        // NOTE: Round down so that the output is an underestimate.
        return
            _shareAmount.mulDivDown(
                _liquidityPool.getTotalPooledEther(),
                totalShares
            );
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _liquidityPool The Etherfi liquidity pool contract.
    /// @param _eETH The eETH contract.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function convertToShares(
        ILiquidityPool _liquidityPool,
        IERC20 _eETH,
        uint256 _baseAmount
    ) internal view returns (uint256) {
        // Get the total supply assets and shares after interest accrues.
        uint256 totalPooledEther = _liquidityPool.getTotalPooledEther();
        if (totalPooledEther == 0) {
            return 0;
        }

        // This calculation matches the implementation of
        // `sharesForAmount(uint256 _amount)` found in the LiquidityPool
        // contract.
        // NOTE: Round down so that the output is an underestimate.
        return
            _baseAmount.mulDivDown(
                IEETH(address(_eETH)).totalShares(),
                totalPooledEther
            );
    }
}
