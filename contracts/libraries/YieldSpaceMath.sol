/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";

// FIXME: This doesn't compute the fee but maybe it should.
//
/// @author Delve
/// @title YieldSpaceMath
/// @notice Math for the YieldSpace pricing model.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
///
/// @dev It is important for developers to attain the pre-requisite knowledge
///      of how this implementation works on the mathematical level. This
///      excerpt attempts to document this pre-requisite knowledge explaining
///      the underpinning mathematical concepts in a parseable manner and
///      relating it directly to the code implementation.
///      For starters, this implementation is based on a paper called
///      "YieldSpace with Yield Bearing Vaults" or more casually "Modified
///      YieldSpace" (MYS). It can be found at the following link.
///
///      https://hackmd.io/lRZ4mgdrRgOpxZQXqKYlFw?view
///
///      This paper builds on the original YieldSpace paper (YS), "YieldSpace:
///      An Automated Liquidity Provider for Fixed Yield Tokens". It can be
///      found at the following link:
///
///      https://yieldprotocol.com/YieldSpace.pdf
///
///      In these notes, both of these papers will be referenced by in
///      abbreviated form, YS and MYS.
///      _______________________________________________________________________
///      # Overview #
///
///      YS introduces the concept of "fyTokens" which conceptualizes a token
///      which redeems for another target asset after a fixed maturity date.
///      We refer to "fyTokens" in this project as "bonds" and readers may also
///      be familiar of them as "principal tokens" from the first implementation
///      of the Element protocol. The target asset is more commonly referred to
///      as "base".
///
///      To exemplify the concept with concrete understanding, a bond at some
///      point prior to maturity may trade at a value of 0.9090... base and
///      is expected to accrete to a value of 1 base at maturity. A trader who
///      purchases that bond, provided they hold it until maturity, will be
///      guaranteed a rate of return based on the value difference from the
///      time of purchase to maturity. Using the previous figures, 1 - 0.9090..
///      = 0.0909.. which as a percentage value of the purchase price is 10%.
///
///      YS envisions an constant function market maker (CFMM) which maintains
///      reserves of bond and base and incorporates time as a function of how
///      these reserves should trade against one another. This formula is
///      commonly referred to as an "invariant" which is generally explained as
///      a mathematical rule which must always be upheld and enforces properties
///      on how trading should occur. YS introduces the "constant power sum"
///      invariant which is written as:
///
///      x^(1-t) + y^(1-t) = k
///
///      One large critique of this model is because all base assets are held in
///      reserve, there is effectively zero capital utilisation and liquidity
///      providers would only earn a return from fees laid on bond purchases.
///
///      MYS solves this capital utilisation problem by using reserves of
///      "shares" instead of base. A share is a unit claim to a unit deposit of
///      base in some interest accruing enterprise *and* the variable interest
///      accrued on that deposit. Concrete examples of this are aDAI or cDAI for
///      which the DAI depositors to the Aave and Compound protocols generate a
///      rate of return over time from borrowers paying fees for borrowing those
///      deposits.
///
///      With this, under the MYS model, all deposits of base would be invested
///      in some "vault" (Yield bearing Vault) and the shares given in return
///      for those deposits are held in reserve, thereby collectively accruing
///      variable interest for the pool. This of course modifes the "constant
///      power sum" invariant to incorporate shares as a pricing mechanic for
///      bonds and base.
///      _______________________________________________________________________
///      # Definitions #
///
///      X, x  :- "X" is the mathematical notation for a base assets, reserves
///               of base are notated as "x"
///      Y, y  :- "Y" is the mathematical notation for a bond assets, reserves
///               of bonds are notated as "y"
///      Z, z  :- "Z" is the mathematical notation for a share assets, reserves
///                of shares are notated as "z"
///      t     :- "t" represents time until to maturity and is normalized such
///               that 0 <= t < 1.
///      c     :- "c" is the conversion rate between base and share reserves in
///               a vault. It is expected to increase over time with respect to
///               shares
///      μ     :- "μ" is typically the initial value of "c" at the beginning of
///               the market normalizes the accrual of interest throughout the
///               market duration.
///      p     :- "p" is defined in context of the invariant relationship of
///               base and bond reserves. This means that as a general principle
///               price is defined as the rate of change between the x and y.
///               More simply, if some quantity of x is added to the pool, some
///               quantity of y must leave. These are denoted as dx and dy and
///               therefore expressed in the equation:
///
///                 p_x = -dy/dx
///
///               Note that as y is leaving the pool, a negative dy value is
///               used. To exemplify this:
///
///                 dx = 600,
///                 dy = -200
///                 p_x = -(-200/600) = 0.333...
///
///               A point of confusion in the MYS paper is this is defined as an
///               inversion. The definition of above prices base in terms of
///               bonds, whereas MYS uses the inverts the formula to price bond
///               in terms of base.
///
///                 p_y = -1 / (dy / dx)
///                 p_y = -1 / (-200 / 600) = 3
///
///               The definition provided in the YS paper is meant to be
///               generalised to illustrate how invariants can be conceived but
///               the most simple example is how the constant product formula
///               expresses p to maintain equal value of reserves of a pool
///
///                 p_x = y/x
///
///      r     :- "r" is defined in the YS paper as the ratio the reserve of
///               bonds to the reserve of base held in the pool. Mathematically:
///
///               r = y/x - 1
///
///               Supposing, bond reserves of 11000 and base reserves of
///               10,000:
///
///               r = (11000 / 10000) - 1 = 1.1 - 1 = 0.1 = 10%
///
///      _______________________________________________________________________
///      # The YieldSpace invariant #
///
///      The "constant power sum" formula inherits the idea from the constant
///      product formula where "price" is defined as a function of the reserves.
///      In Yieldspace, it is desired that the interest rate is a function of
///      the reserves which is described clearly in the definition of "r".
///
///      Thereby, the interest rate of bonds can be derived using the reserves
///      as a pricing mechanism and the time to maturity of those bonds.
///
///        r = p^(1/t) - 1
///
///      We can refactor this:
///
///        | y/x - 1 = p^(1/t) - 1
///        | y/x = p^(1/t)
///        | (y/x)^t = p
///        | p = (y/x)^t
///
///      Example:
///
///        y = 110
///        x = 100
///
///        r = 110/100 - 1 = 0.1, implying 10% annualized interest
///
///        t = 10%; p = (110/100)^(0.1) = 1.00957658278 = ~0.957..% accrued
///        t = 50%; p = (110/100)^(0.5) = 1.04880884817 = ~4.881..% accrued
///        t = 80%; p = (110/100)^(0.8) = 1.0792303453  = ~7.923..% accrued
///        t = 100%; p = (110/100)^(1) = 1.1            = ~10% accrued
///
///      This should illustrate how the pricing formula derives the accrual of
///      interest over the duration t.
///
///      To derive the invariant formula:
///
///      We know:
///
///        p = -(dy/dx)
///
///      Which can be refactored to
///
///        -(dy/dx) = (y/x)^(t)
///
///      The derivment and solution to this equation is documented in the
///      appendix of the YS paper and solves to:
///
///      x^(1-t) + y^(1-t) = k
///
///
///
///
/// This implementation of the YieldSpace equation is based on the
///      "Modified YieldSpace paper"
///
///
///
/// It is important to note that this implementation utilises the modified
/// YieldSpace invariant and not the original. See the link below:
///
///   https://hackmd.io/lRZ4mgdrRgOpxZQXqKYlFw?view
///
/// -:: Definitions ::-
///
/// -::| X, x |::-
///     Base asset (X) and reserves (x), e.g DAI/USDC/WETH/etc
///
/// -::| Y, y |::-
///     A "bond" (Y) (named "fyToken" in the YieldSpace paper) and a reserve
///     amount (y) is a synthetic token which redeems for a target "base" asset
///     (X) after a fixed maturity date.
///     The price of a bond implies a discounted interest rate relative to the
///     "base" asset and is expected to converge to a 1:1 at maturity
///     e.g A bond may be priced as 0.9 base at some time before maturity and
///     will accrete to 1 at maturity
///
/// -::| t |::-
///     "t" represents the time until to maturity. It is assumed that t is
///     normalized s.t 0 <= t < 1. "maturity" is defined as t = 1
///
/// -::| Z, z |::-
///     A "share" (Z) represents a unit claim to a deposited amount of base +
///     interest in a pool. This pool is known as a "Yield bearing vault" (vault)
///     Deposits are invested into capital accruing activities and accrued
///     interest is shared pro-rata to the number of shares depositors have.
///     It is presumed that the redeemable amount of base for a unit share
///     should increase monotonically over time. Examples of this are aDai,
///     cDai, yvDAI.
///
/// -::| c |::-
///     "c" is the conversion rate between the reserves of shares and base in a
///     vault. Example: x = 110, z = 100, c = x/z = 1.1
///
/// -::| μ |::-
///     "μ" is a normalizing constant which is used to give the interest rate a
///     reasonable relationship with the base value of the shares. Typically this
///     is c_0, (c when t = 0)
///
/// -::| r |::-
///     "r" represents the marginal interest rate of bonds derived from the
///     reserves of bonds and base in the pool. In the original yieldspace paper
///     this was derived by the equation:
///
///     r = (y / x) - 1
///
///     The addendum hackmd recontextualizes this in terms of shares:
///
///     r = (y / (μ * z)) - 1
///
///     and again with respect to the base assets
///
///     r = ((c * y) / (μ * x)) - 1
///
/// -::| p |::-
///     "p" represents price, the ratio for which assets in a pool are
///     exchanged. As highlighted in the YieldSpace paper, this is expressed
///     abstractly in the form of a differential equation to attain some desired
///     property in how assets are traded. The general definition:
///
///     p_x = -(dy/dx), p equals the ratio of the decrease in y reserves to the
///     increase in x reserves. e.g, dy = -5, dx = 2, p_x = 2.5.
///
///     Also note the inverse relationship, p_y = -(1/(dy/dx)), with the same
///     figures, p_y = 0.4
///
///     Amongst other examples in the Yieldspace paper, the property to define
///     pool reserves to be equal in value is given by the definition:
///
///     p_x * x = y, this is rewritten knowing the abstract pricing formula into
///     the below differential equation
///
///     -dy/dx = y/x
///
///
///     The most important definition for us to understand is the formula for
///     how at a given price
///
///     of bonds (Y) in terms of base (X). It is
///     defined as:
///
///     p = (1 / -f'(x))
///
///     -f'(x) can be rewritten as -dy/dx which is the ratio of the decrease in
///     y reserves to the increase in x reserves. As this definition is used to
///     specify bonds in terms of base, the definition as defined in the
///     YieldSpace paper is inverted.
///
///
///
///
/// This library provides 4 trade calculations defined in 2 functions.
/// These are:
///
///   1. calculateOutGivenIn - in = bonds  | out = shares
///   2. calculateOutGivenIn - in = shares | out = bonds
///   3. calculateInGivenOut - in = shares | out = bonds
///   4. calculateInGivenOut - in = bonds  | out = shares
///
///
///   Δz = z - 1/μ( ( c/μ * (μz)^(1 - t) + y^(1 - t) - (y + Δy)^(1 - t) ) / c/μ )^(1 / (1 - t))
/// NOTE: * indicates the "amount" parameter in each case
///
library YieldSpaceMath {
    using FixedPointMath for uint256;

    /// Calculates the amount of bond a user would get for given amount of shares.
    /// @param _shareReserves yield bearing vault shares reserve amount, unit is shares
    /// @param _bondReserves bond reserves amount, unit is the face value in underlying
    /// @param _bondReserveAdjustment An optional adjustment to the reserve which MUST have units of underlying.
    /// @param _amountIn amount to be traded, if bonds in the unit is underlying, if shares in the unit is shares
    /// @param _stretchedTimeElapsed Amount of time elapsed since term start
    /// @param _c price of shares in terms of their base
    /// @param _mu Normalization factor -- starts as c at initialization
    /// @param _isBondOut determines if the output is bond or shares
    /// @return Amount of shares/bonds
    function calculateOutGivenIn(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _bondReserveAdjustment,
        uint256 _amountIn,
        uint256 _stretchedTimeElapsed,
        uint256 _c,
        uint256 _mu,
        bool _isBondOut
    ) internal pure returns (uint256) {
        // c / mu
        uint256 cDivMu = _c.divDown(_mu);
        // Adjust the bond reserve, optionally shifts the curve around the
        // inflection point
        _bondReserves = _bondReserves.add(_bondReserveAdjustment);
        // (c / mu) * (mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau)
        uint256 k = _k(
            cDivMu,
            _mu,
            _shareReserves,
            _stretchedTimeElapsed,
            _bondReserves
        );

        if (_isBondOut) {
            // (mu * (shareReserves + amountIn))^(1 - tau)
            _shareReserves = _mu.mulDown(_shareReserves.add(_amountIn)).pow(
                _stretchedTimeElapsed
            );
            // (c / mu) * (mu * (shareReserves + amountIn))^(1 - tau)
            _shareReserves = cDivMu.mulDown(_shareReserves);
            // NOTE: k - shareReserves >= 0 to avoid a complex number
            // ((c / mu) * (mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (c / mu) * (mu * (shareReserves + amountIn))^(1 - tau))^(1 / (1 - tau)))
            uint256 newBondReserves = k.sub(_shareReserves).pow(
                FixedPointMath.ONE_18.divDown(_stretchedTimeElapsed)
            );
            // NOTE: bondReserves - newBondReserves >= 0, but I think avoiding a complex number in the step above ensures this never happens
            // bondsOut = bondReserves - ( (c / mu) * (mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (c / mu) * (mu * (shareReserves + shareIn))^(1 - tau))^(1 / (1 - tau)))
            return _bondReserves.sub(newBondReserves);
        } else {
            // (bondReserves + amountIn)^(1 - tau)
            _bondReserves = _bondReserves.add(_amountIn).pow(
                _stretchedTimeElapsed
            );
            // NOTE: k - bondReserves >= 0 to avoid a complex number
            // (((mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (bondReserves + amountIn)^(1 - tau)) / (c / mu))^(1 / (1 - tau)))
            uint256 newShareReserves = k.sub(_bondReserves).divDown(cDivMu).pow(
                FixedPointMath.ONE_18.divDown(_stretchedTimeElapsed)
            );
            // (((mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (bondReserves + bondIn)^(1 - tau) ) / (c / mu))^(1 / (1 - tau))) / mu
            newShareReserves = newShareReserves.divDown(_mu);
            // NOTE: shareReserves - sharesOut >= 0, but I think avoiding a complex number in the step above ensures this never happens
            //
            // Δz = z - 1/μ( ( c/μ * (μz)^(1 - t) + y^(1 - t) - (y + Δy)^(1 - t) ) / c/μ )^(1 / (1 - t))
            //
            // sharesOut = shareReserves - (((c / mu) * (mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (bondReserves + bondIn)^(1 - tau) ) / (c / mu))^(1 / (1 - tau))) / mu
            return _shareReserves.sub(newShareReserves);
        }
    }

    /// @dev Calculates the amount of an asset that will be received given a
    ///      specified amount of the other asset given the current AMM reserves.
    /// @param _shareReserves yield bearing vault shares reserve amount, unit is shares
    /// @param _bondReserves bond reserves amount, unit is the face value in underlying
    /// @param _bondReserveAdjustment An optional adjustment to the reserve which MUST have units of underlying.
    /// @param _amountOut amount to be received, if bonds in the unit is underlying, if shares in the unit is shares
    /// @param _stretchedTimeElapsed Amount of time elapsed since term start
    /// @param _c price of shares in terms of their base
    /// @param _mu Normalization factor -- starts as c at initialization
    /// @param _isBondIn determines if the input is bond or shares
    /// @return Amount of shares/bonds
    function calculateInGivenOut(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _bondReserveAdjustment,
        uint256 _amountOut,
        uint256 _stretchedTimeElapsed,
        uint256 _c,
        uint256 _mu,
        bool _isBondIn
    ) internal pure returns (uint256) {
        // c / mu
        uint256 cDivMu = _c.divDown(_mu);
        // Adjust the bond reserve, optionally shifts the curve around the inflection point
        _bondReserves = _bondReserves.add(_bondReserveAdjustment);
        // (c / mu) * (mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau)
        uint256 k = _k(
            cDivMu,
            _mu,
            _shareReserves,
            _stretchedTimeElapsed,
            _bondReserves
        );
        if (_isBondIn) {
            // (mu * (shareReserves - amountOut))^(1 - tau)
            _shareReserves = _mu.mulDown(_shareReserves.sub(_amountOut)).pow(
                _stretchedTimeElapsed
            );
            // (c / mu) * (mu * (shareReserves - amountOut))^(1 - tau)
            _shareReserves = cDivMu.mulDown(_shareReserves);
            // NOTE: k - shareReserves >= 0 to avoid a complex number
            // ((c / mu) * (mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (c / mu) * (mu*(shareReserves - amountOut))^(1 - tau))^(1 / (1 - tau)))
            uint256 newBondReserves = k.sub(_shareReserves).pow(
                FixedPointMath.ONE_18.divDown(_stretchedTimeElapsed)
            );
            // NOTE: newBondReserves - bondReserves >= 0, but I think avoiding a complex number in the step above ensures this never happens
            // bondIn = ((c / mu) * (mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (c / mu) * (mu * (shareReserves - shareOut))^(1 - tau))^(1 / (1 - tau))) - bondReserves
            return newBondReserves.sub(_bondReserves);
        } else {
            // (bondReserves - amountOut)^(1 - tau)
            _bondReserves = _bondReserves.sub(_amountOut).pow(
                _stretchedTimeElapsed
            );
            // NOTE: k - newScaledBondReserves >= 0 to avoid a complex number
            // (((mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (bondReserves - amountOut)^(1 - tau) ) / (c / mu))^(1 / (1 - tau)))
            uint256 newShareReserves = k.sub(_bondReserves).divDown(cDivMu).pow(
                FixedPointMath.ONE_18.divDown(_stretchedTimeElapsed)
            );
            // (((mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (bondReserves - amountOut)^(1 - tau) ) / (c / mu))^(1 / (1 - tau))) / mu
            newShareReserves = newShareReserves.divDown(_mu);
            // NOTE: newShareReserves - shareReserves >= 0, but I think avoiding a complex number in the step above ensures this never happens
            // sharesIn = (((c / mu) * (mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (bondReserves - bondOut)^(1 - tau) ) / (c / mu))^(1 / (1 - tau))) / mu - shareReserves
            return newShareReserves.sub(_shareReserves);
        }
    }

    /// @dev Helper function to derive invariant constant k
    /// @param _cDivMu Normalized price of shares in terms of base
    /// @param _mu Normalization factor -- starts as c at initialization
    /// @param _shareReserves Yield bearing vault shares reserve amount, unit is shares
    /// @param _stretchedTimeElapsed Amount of time elapsed since term start
    /// @param _bondReserves Bond reserves amount, unit is the face value in underlying
    /// returns k
    function _k(
        uint256 _cDivMu,
        uint256 _mu,
        uint256 _shareReserves,
        uint256 _stretchedTimeElapsed,
        uint256 _bondReserves
    ) private pure returns (uint256) {
        /// k = (c / mu) * (mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau)
        return
            _cDivMu
                .mulDown(_mu.mulDown(_shareReserves).pow(_stretchedTimeElapsed))
                .add(_bondReserves.pow(_stretchedTimeElapsed));
    }
}
