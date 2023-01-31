/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { YieldSpaceMath } from "contracts/libraries/YieldSpaceMath.sol";

// FIXME:
//
// The matrix of uses of flat+curve includes cases that should never occur.
// In particular, if isBondOut && t > 0 or isBondIn && t > 0, then the flat
// part refers to base tokens and the model doesn't make sense.
//
/// @notice Math for the Hyperdrive pricing model.
/// @author Element Finance
library HyperdriveMath {
    using FixedPointMath for uint256;

    // FIXME: We may need to change the return argument of this contract.
    //
    // FIXME: This needs some TLC. The consumer can compute the market and
    //        user deltas but I'm not sure that they should have to.
    function calculateOutGivenIn(
        uint256 shareReserves,
        uint256 bondReserves,
        uint256 bondReserveAdjustment,
        uint256 amountIn,
        uint256 t,
        uint256 s,
        uint256 c,
        uint256 mu,
        bool isBondOut
    ) internal pure returns (
        uint256 poolBaseDelta,
        uint256 poolBondDelta,
        uint256 userDelta
    ) {
        uint256 flat = amountIn.mulDown(t);
        uint256 curveIn = amountIn.mulDown(FixedPointMath.ONE_18.sub(t))
        // FIXME: Update the reserves first.
        uint256 curveOut = YieldSpaceMath.calculateOutGivenIn(
            shareReserves,
            bondReserves,
            bondReserveAdjustment,
            curveIn,
            FixedPointMath.ONE_18,
            s,
            c,
            mu,
            isBondOut
        );
        if (isBondOut) {
            return (
                amountIn,
                curveOut,
                flat.add(curveOut)
            );
        } else {
            return (
                flat.add(curveOut),
                curveIn,
                flat.add(curveOut)
            );
        }
    }

    function calculateInGivenOut(
        uint256 shareReserves,
        uint256 bondReserves,
        uint256 bondReserveAdjustment,
        uint256 amountOut,
        uint256 t,
        uint256 s,
        uint256 c,
        uint256 mu,
        bool isBondIn
    ) internal pure returns (
        uint256 poolBaseDelta,
        uint256 poolBondDelta,
        uint256 userDelta
    ) {
        uint256 flat = amountOut.mulDown(t);
        uint256 curveOut = amountIn.mulDown(FixedPointMath.ONE_18.sub(t))
        // FIXME: Update the reserves first.
        uint256 curveIn = YieldSpaceMath.calculateInGivenOut(
            shareReserves,
            bondReserves,
            bondReserveAdjustment,
            curveOut,
            FixedPointMath.ONE_18,
            s,
            c,
            mu,
            isBondIn
        );
        if (isBondIn) {
            return (
                amountOut,
                curveIn,
                flat.add(curveIn)
            );
        } else {
            return (
                flat.add(curveIn),
                curveIn,
                flat.add(curveIn)
            );
        }
    }
}
