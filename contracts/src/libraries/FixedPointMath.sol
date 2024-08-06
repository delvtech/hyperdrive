/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IHyperdrive } from "../interfaces/IHyperdrive.sol";
import { SafeCast } from "./SafeCast.sol";

uint256 constant ONE = 1e18;

/// @author DELV
/// @title FixedPointMath
/// @notice A fixed-point math library.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
library FixedPointMath {
    using FixedPointMath for uint256;
    using SafeCast for uint256;

    uint256 internal constant MAX_UINT256 = 2 ** 256 - 1;

    /// @param x Fixed point number in 1e18 format.
    /// @param y Fixed point number in 1e18 format.
    /// @param denominator Fixed point number in 1e18 format.
    /// @return z The result of x * y / denominator rounded down.
    function mulDivDown(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            // Equivalent to require(denominator != 0 && (y == 0 || x <= type(uint256).max / y))
            if iszero(
                mul(denominator, iszero(mul(y, gt(x, div(MAX_UINT256, y)))))
            ) {
                revert(0, 0)
            }

            // Divide x * y by the denominator.
            z := div(mul(x, y), denominator)
        }
    }

    /// @param a Fixed point number in 1e18 format.
    /// @param b Fixed point number in 1e18 format.
    /// @return Result of a * b rounded down.
    function mulDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return (mulDivDown(a, b, ONE));
    }

    /// @param a Fixed point number in 1e18 format.
    /// @param b Fixed point number in 1e18 format.
    /// @return Result of a / b rounded down.
    function divDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return (mulDivDown(a, ONE, b)); // Equivalent to (a * 1e18) / b rounded down.
    }

    /// @param x Fixed point number in 1e18 format.
    /// @param y Fixed point number in 1e18 format.
    /// @param denominator Fixed point number in 1e18 format.
    /// @return z The result of x * y / denominator rounded up.
    function mulDivUp(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            // Equivalent to require(denominator != 0 && (y == 0 || x <= type(uint256).max / y))
            if iszero(
                mul(denominator, iszero(mul(y, gt(x, div(MAX_UINT256, y)))))
            ) {
                revert(0, 0)
            }

            // If x * y modulo the denominator is strictly greater than 0,
            // 1 is added to round up the division of x * y by the denominator.
            z := add(
                gt(mod(mul(x, y), denominator), 0),
                div(mul(x, y), denominator)
            )
        }
    }

    /// @param a Fixed point number in 1e18 format.
    /// @param b Fixed point number in 1e18 format.
    /// @return The result of a * b rounded up.
    function mulUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return (mulDivUp(a, b, ONE));
    }

    /// @param a Fixed point number in 1e18 format.
    /// @param b Fixed point number in 1e18 format.
    /// @return The result of a / b rounded up.
    function divUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return (mulDivUp(a, ONE, b));
    }

    /// @dev Exponentiation (x^y) with unsigned 18 decimal fixed point base and exponent.
    /// @param x Fixed point number in 1e18 format.
    /// @param y Fixed point number in 1e18 format.
    /// @return The result of x^y.
    function pow(uint256 x, uint256 y) internal pure returns (uint256) {
        // If the exponent is 0, return 1.
        if (y == 0) {
            return ONE;
        }

        // If the base is 0, return 0.
        if (x == 0) {
            return 0;
        }

        // Using properties of logarithms we calculate x^y:
        // -> ln(x^y) = y * ln(x)
        // -> e^(y * ln(x)) = x^y
        int256 y_int256 = y.toInt256(); // solhint-disable-line var-name-mixedcase

        // Compute y*ln(x)
        // Any overflow for x will be caught in ln() in the initial bounds check
        int256 lnx = ln(x.toInt256());
        int256 ylnx;
        assembly ("memory-safe") {
            ylnx := mul(y_int256, lnx)
        }
        ylnx /= int256(ONE);

        // Calculate exp(y * ln(x)) to get x^y
        return uint256(exp(ylnx));
    }

    /// @dev Computes e^x in 1e18 fixed point.
    /// @dev Credit to Remco (https://github.com/recmo/experiment-solexp/blob/main/src/FixedPointMathLib.sol)
    /// @param x Fixed point number in 1e18 format.
    /// @return r The result of e^x.
    function exp(int256 x) internal pure returns (int256 r) {
        unchecked {
            // When the result is < 0.5 we return zero. This happens when
            // x <= floor(log(0.5e18) * 1e18) ~ -42e18
            if (x <= -42139678854452767551) return 0;

            // When the result is > (2**255 - 1) / 1e18 we can not represent it as an
            // int. This happens when x >= floor(log((2**255 - 1) / 1e18) * 1e18) ~ 135.
            if (x >= 135305999368893231589)
                revert IHyperdrive.ExpInvalidExponent();

            // x is now in the range (-42, 136) * 1e18. Convert to (-42, 136) * 2**96
            // for more intermediate precision and a binary basis. This base conversion
            // is a multiplication by 1e18 / 2**96 = 5**18 / 2**78.
            x = (x << 78) / 5 ** 18;

            // Reduce range of x to (-½ ln 2, ½ ln 2) * 2**96 by factoring out powers
            // of two such that exp(x) = exp(x') * 2**k, where k is an integer.
            // Solving this gives k = round(x / log(2)) and x' = x - k * log(2).
            // Note: 54916777467707473351141471128 = 2^96 ln(2).
            int256 k = ((x << 96) / 54916777467707473351141471128 + 2 ** 95) >>
                96;
            x = x - k * 54916777467707473351141471128;

            // k is in the range [-61, 195].

            // Evaluate using a (6, 7)-term rational approximation.
            // p is made monic, we'll multiply by a scale factor later.
            int256 y = x + 1346386616545796478920950773328;
            y = ((y * x) >> 96) + 57155421227552351082224309758442;
            int256 p = y + x - 94201549194550492254356042504812;
            p = ((p * y) >> 96) + 28719021644029726153956944680412240;
            p = p * x + (4385272521454847904659076985693276 << 96);

            // We leave p in 2**192 basis so we don't need to scale it back up for the division.
            int256 q = x - 2855989394907223263936484059900;
            q = ((q * x) >> 96) + 50020603652535783019961831881945;
            q = ((q * x) >> 96) - 533845033583426703283633433725380;
            q = ((q * x) >> 96) + 3604857256930695427073651918091429;
            q = ((q * x) >> 96) - 14423608567350463180887372962807573;
            q = ((q * x) >> 96) + 26449188498355588339934803723976023;

            /// @solidity memory-safe-assembly
            assembly {
                // Div in assembly because solidity adds a zero check despite the unchecked.
                // The q polynomial won't have zeros in the domain as all its roots are complex.
                // No scaling is necessary because p is already 2**96 too large.
                r := sdiv(p, q)
            }

            // r should be in the range (0.09, 0.25) * 2**96.

            // We now need to multiply r by:
            // * the scale factor s = ~6.031367120.
            // * the 2**k factor from the range reduction.
            // * the 1e18 / 2**96 factor for base conversion.
            // We do this all at once, with an intermediate result in 2**213
            // basis, so the final right shift is always by a positive amount.
            r = ((uint256(r) *
                3822833074963236453042738258902158003155416615667) >>
                uint256(195 - k)).toInt256();
        }
    }

    /// @dev Computes ln(x) in 1e18 fixed point.
    /// @dev Credit to Remco (https://github.com/recmo/experiment-solexp/blob/main/src/FixedPointMathLib.sol)
    /// @dev Reverts if x is negative or zero.
    /// @param x Fixed point number in 1e18 format.
    /// @return r Result of ln(x).
    function ln(int256 x) internal pure returns (int256 r) {
        unchecked {
            if (x <= 0) {
                revert IHyperdrive.LnInvalidInput();
            }

            // We want to convert x from 10**18 fixed point to 2**96 fixed point.
            // We do this by multiplying by 2**96 / 10**18. But since
            // ln(x * C) = ln(x) + ln(C), we can simply do nothing here
            // and add ln(2**96 / 10**18) at the end.

            // This step inlines the `ilog2` call in Remco's implementation:
            // https://github.com/recmo/experiment-solexp/blob/bbc164fb5ec078cfccf3c71b521605106bfae00b/src/FixedPointMathLib.sol#L57-L68
            //
            /// @solidity memory-safe-assembly
            assembly {
                r := shl(7, lt(0xffffffffffffffffffffffffffffffff, x))
                r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, x))))
                r := or(r, shl(5, lt(0xffffffff, shr(r, x))))
                r := or(r, shl(4, lt(0xffff, shr(r, x))))
                r := or(r, shl(3, lt(0xff, shr(r, x))))
                r := or(r, shl(2, lt(0xf, shr(r, x))))
                r := or(r, shl(1, lt(0x3, shr(r, x))))
                r := or(r, lt(0x1, shr(r, x)))
            }

            // Reduce range of x to [1, 2) * 2**96
            // ln(2^k * x) = k * ln(2) + ln(x)
            int256 k = r - 96;
            x <<= uint256(159 - k);
            x = (uint256(x) >> 159).toInt256();

            // Evaluate using a (8, 8)-term rational approximation.
            // p is made monic, we will multiply by a scale factor later.
            int256 p = x + 3273285459638523848632254066296;
            p = ((p * x) >> 96) + 24828157081833163892658089445524;
            p = ((p * x) >> 96) + 43456485725739037958740375743393;
            p = ((p * x) >> 96) - 11111509109440967052023855526967;
            p = ((p * x) >> 96) - 45023709667254063763336534515857;
            p = ((p * x) >> 96) - 14706773417378608786704636184526;
            p = p * x - (795164235651350426258249787498 << 96);

            // We leave p in 2**192 basis so we don't need to scale it back up for the division.
            // q is monic by convention.
            int256 q = x + 5573035233440673466300451813936;
            q = ((q * x) >> 96) + 71694874799317883764090561454958;
            q = ((q * x) >> 96) + 283447036172924575727196451306956;
            q = ((q * x) >> 96) + 401686690394027663651624208769553;
            q = ((q * x) >> 96) + 204048457590392012362485061816622;
            q = ((q * x) >> 96) + 31853899698501571402653359427138;
            q = ((q * x) >> 96) + 909429971244387300277376558375;
            /// @solidity memory-safe-assembly
            assembly {
                // Div in assembly because solidity adds a zero check despite the unchecked.
                // The q polynomial is known not to have zeros in the domain.
                // No scaling required because p is already 2**96 too large.
                r := sdiv(p, q)
            }

            // r is in the range (0, 0.125) * 2**96

            // Finalization, we need to:
            // * multiply by the scale factor s = 5.549…
            // * add ln(2**96 / 10**18)
            // * add k * ln(2)
            // * multiply by 10**18 / 2**96 = 5**18 >> 78

            // mul s * 5e18 * 2**96, base is now 5**18 * 2**192
            r *= 1677202110996718588342820967067443963516166;
            // add ln(2) * k * 5e18 * 2**192
            r +=
                16597577552685614221487285958193947469193820559219878177908093499208371 *
                k;
            // add ln(2**96 / 10**18) * 5e18 * 2**192
            r += 600920179829731861736702779321621459595472258049074101567377883020018308;
            // base conversion: mul 2**18 / 2**192
            r >>= 174;
        }
    }

    /// @dev Updates a weighted average by adding or removing a weighted delta.
    /// @param _totalWeight The total weight before the update.
    /// @param _deltaWeight The weight of the new value.
    /// @param _average The weighted average before the update.
    /// @param _delta The new value.
    /// @return average The new weighted average.
    function updateWeightedAverage(
        uint256 _average,
        uint256 _totalWeight,
        uint256 _delta,
        uint256 _deltaWeight,
        bool _isAdding
    ) internal pure returns (uint256 average) {
        // If the delta weight is zero, the average does not change.
        if (_deltaWeight == 0) {
            return _average;
        }

        // If the delta weight should be added to the total weight, we compute
        // the weighted average as:
        //
        // average = (totalWeight * average + deltaWeight * delta) /
        //           (totalWeight + deltaWeight)
        if (_isAdding) {
            // NOTE: Round down to underestimate the average.
            average = (_totalWeight.mulDown(_average) +
                _deltaWeight.mulDown(_delta)).divDown(
                    _totalWeight + _deltaWeight
                );

            // An important property that should always hold when we are adding
            // to the average is:
            //
            // min(_delta, _average) <= average <= max(_delta, _average)
            //
            // To ensure that this is always the case, we clamp the weighted
            // average to this range. We don't have to worry about the
            // case where average > _delta.max(average) because rounding down when
            // computing this average makes this case infeasible.
            uint256 minAverage = _delta.min(_average);
            if (average < minAverage) {
                average = minAverage;
            }
        }
        // If the delta weight should be subtracted from the total weight, we
        // compute the weighted average as:
        //
        // average = (totalWeight * average - deltaWeight * delta) /
        //           (totalWeight - deltaWeight)
        else {
            if (_totalWeight == _deltaWeight) {
                return 0;
            }

            // NOTE: Round down to underestimate the average.
            average = (_totalWeight.mulDown(_average) -
                _deltaWeight.mulUp(_delta)).divDown(
                    _totalWeight - _deltaWeight
                );
        }
    }

    /// @dev Calculates the minimum of two values.
    /// @param a The first value.
    /// @param b The second value.
    /// @return The minimum of the two values.
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? b : a;
    }

    /// @dev Calculates the maximum of two values.
    /// @param a The first value.
    /// @param b The second value.
    /// @return The maximum of the two values.
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /// @dev Calculates the minimum of two values.
    /// @param a The first value.
    /// @param b The second value.
    /// @return The minimum of the two values.
    function min(int256 a, int256 b) internal pure returns (int256) {
        return a > b ? b : a;
    }

    /// @dev Calculates the maximum of two values.
    /// @param a The first value.
    /// @param b The second value.
    /// @return The maximum of the two values.
    function max(int256 a, int256 b) internal pure returns (int256) {
        return a > b ? a : b;
    }
}
