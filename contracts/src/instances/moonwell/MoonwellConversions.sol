// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;
import { console2 as console } from "forge-std/console2.sol";

import { IMToken } from "../../interfaces/IMoonwell.sol";
import { IMoonwellHyperdrive } from "../../interfaces/IMoonwellHyperdrive.sol";
import { IERC20 } from "../../interfaces/IERC20.sol";
import { FixedPointMath } from "../../libraries/FixedPointMath.sol";

/// @author DELV
/// @title MoonwellConversions
/// @notice The conversion logic for the  Moonwell Hyperdrive integration.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library MoonwellConversions {
    using FixedPointMath for uint256;

    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function convertToBase(
        IMToken _vaultSharesToken,
        uint256 _shareAmount
    ) internal view returns (uint256) {
        // revert IHyperdrive.UnsupportedToken();
        return _shareAmount.mulDown(exchangeRateCurrent(_vaultSharesToken));
        // return _shareAmount.mulDown(_vaultSharesToken.exchangeRateStored());
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function convertToShares(
        IMToken _vaultSharesToken,
        uint256 _baseAmount
    ) internal view returns (uint256) {
        // revert IHyperdrive.UnsupportedToken();
        return _baseAmount.divDown(exchangeRateCurrent(_vaultSharesToken));
        // return _baseAmount.divDown(_vaultSharesToken.exchangeRateStored());
    }

    /**
     * @notice Estimates exchange rate after applying accrued interest to total
     *   borrows and reserves.
     * @dev This calculates interest accrued from the last checkpointed block
     *   up to the current block.
     */
    function exchangeRateCurrent(
        IMToken vaultSharesToken
    ) internal view returns (uint256) {
        /* Remember the initial block timestamp */
        uint256 accrualBlockTimestampPrior = vaultSharesToken
            .accrualBlockTimestamp();
        console.log("current block timestamp: ", block.timestamp);
        console.log("accrualBlockTimestamp:   ", accrualBlockTimestampPrior);

        /* Short-circuit accumulating 0 interest */
        if (accrualBlockTimestampPrior == block.timestamp) {
            return vaultSharesToken.exchangeRateStored();
        }

        /* Read the previous values out of storage */
        uint256 cashPrior = vaultSharesToken.getCash();
        uint256 borrowsPrior = vaultSharesToken.totalBorrows();
        uint256 reservesPrior = vaultSharesToken.totalReserves();
        uint256 borrowIndexPrior = vaultSharesToken.borrowIndex();
        uint256 totalSupply = vaultSharesToken.totalSupply();

        /* Calculate the current borrow interest rate */
        uint256 borrowRate = vaultSharesToken.interestRateModel().getBorrowRate(
            cashPrior,
            borrowsPrior,
            reservesPrior
        );

        /* Calculate the number of blocks elapsed since the last accrual */
        uint256 blockDelta = (block.timestamp - accrualBlockTimestampPrior) *
            1e18;

        /*
         * Calculate the interest accumulated into borrows and reserves and the new index:
         *  simpleInterestFactor = borrowRate * blockDelta
         *  interestAccumulated = simpleInterestFactor * totalBorrows
         *  totalBorrowsNew = interestAccumulated + totalBorrows
         *  totalReservesNew = interestAccumulated * reserveFactor + totalReserves
         *  borrowIndexNew = simpleInterestFactor * borrowIndex + borrowIndex
         */

        uint256 simpleInterestFactor = borrowRate.mulDown(blockDelta);
        uint256 interestAccumulated = simpleInterestFactor.mulDown(
            borrowsPrior
        );
        uint256 totalBorrowsNew = interestAccumulated + borrowsPrior;
        uint256 reserveFactor = vaultSharesToken.reserveFactorMantissa();
        uint256 totalReservesNew = interestAccumulated.mulDown(reserveFactor) +
            reservesPrior;
        // uint256 borrowIndexNew = simpleInterestFactor.mulDown(borrowIndexPrior) + borrowIndexPrior;

        // console.log("borrowRate:            ", borrowRate);
        // console.log("blockDelta:            ", blockDelta);
        // console.log("simpleInterestFactor:  ", simpleInterestFactor);
        // console.log("interestAccumulated:   ", interestAccumulated);
        // console.log("totalBorrowsNew:       ", totalBorrowsNew);
        // console.log("reserveFactor:         ", reserveFactor);
        // console.log("totalReservesNew:      ", totalReservesNew);
        /* exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply */
        uint256 sharesFactor = cashPrior + totalBorrowsNew - totalReservesNew;
        return sharesFactor.divDown(totalSupply);
    }
}
