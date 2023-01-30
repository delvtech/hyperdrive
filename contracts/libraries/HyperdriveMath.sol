/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";
import { YieldSpaceMath } from "contracts/libraries/YieldSpaceMath.sol";

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
    ) internal pure returns (uint256 result) {
        uint256 flat = amountIn.mulDown(t);
        uint256 curve = YieldSpaceMath.calculateOutGivenIn(
            shareReserves,
            bondReserves,
            bondReserveAdjustment,
            amountIn.mulDown(FixedPointMath.ONE_18.sub(t)),
            FixedPointMath.ONE_18,
            s,
            c,
            mu,
            isBondOut
        );
        return flat.add(curve);
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
        bool isBondOut
    ) internal pure returns (uint256 result) {
        uint256 flat = amountOut.mulDown(t);
        uint256 curve = YieldSpaceMath.calculateInGivenOut(
            shareReserves,
            bondReserves,
            bondReserveAdjustment,
            amountOut.mulDown(FixedPointMath.ONE_18.sub(t)),
            FixedPointMath.ONE_18,
            s,
            c,
            mu,
            isBondOut
        );
        return flat.add(curve);
    }
}
