// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IXRenzoDeposit } from "../../interfaces/IXRenzoDeposit.sol";
import { FixedPointMath } from "../../libraries/FixedPointMath.sol";

// FIXME: Add a @dev section explaining the oracle.
//
/// @author DELV
/// @title EzETHLineaConversions
/// @notice The conversion logic for the EzETH integration on Linea.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library EzETHLineaConversions {
    using FixedPointMath for uint256;

    /// @dev Convert an amount of vault shares to an amount of base.
    /// @param _xRenzoDeposit The xRenzoDeposit contract.
    /// @param _shareAmount The vault shares amount.
    /// @return The base amount.
    function convertToBase(
        IXRenzoDeposit _xRenzoDeposit,
        uint256 _shareAmount
    ) internal view returns (uint256) {
        // Get the last mint price. This is our vault share price.
        uint256 lastMintPrice = getLastMintPrice(_xRenzoDeposit);

        return _shareAmount.mulDown(lastMintPrice);
    }

    /// @dev Convert an amount of base to an amount of vault shares.
    /// @param _xRenzoDeposit The xRenzoDeposit contract.
    /// @param _baseAmount The base amount.
    /// @return The vault shares amount.
    function convertToShares(
        IXRenzoDeposit _xRenzoDeposit,
        uint256 _baseAmount
    ) internal view returns (uint256) {
        // Get the last mint price. This is our vault share price.
        uint256 lastMintPrice = getLastMintPrice(_xRenzoDeposit);

        return _baseAmount.divDown(lastMintPrice);
    }

    /// @dev Gets the last mint price from the xRenzoDeposit contract. This is
    ///      the price that we'll use as our vault share price.
    /// @param _xRenzoDeposit The xRenzoDeposit contract.
    /// @return The last mint price provided by the oracle.
    function getLastMintPrice(
        IXRenzoDeposit _xRenzoDeposit
    ) internal view returns (uint256) {
        // FIXME: What are the historical values for this oracle? Does it ever
        // go down?
        //
        // FIXME: Is this acceptable? Do we need to do anything with the timestamp?
        //
        // FIXME: Regardless of what we do with the timestamp, we need to make a
        // note of what we're doing.
        (uint256 lastPrice, ) = _xRenzoDeposit.getMintRate();
        return lastPrice;
    }
}
