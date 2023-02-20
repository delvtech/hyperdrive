/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import { FixedPointMath } from "contracts/libraries/FixedPointMath.sol";

/// @author Delve
/// @title YieldSpaceMath
/// @notice Math for the YieldSpace pricing model.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
///
/// @dev It is advised for developers to attain the pre-requisite knowledge
///      of how this implementation works on the mathematical level. This
///      excerpt attempts to document this pre-requisite knowledge explaining
///      the underpinning mathematical concepts in a parseable manner and
///      relating it directly to the code implementation.
///      This implementation is based on a paper called "YieldSpace with Yield
///      Bearing Vaults" or more casually "Modified YieldSpace" (MYS). It can be
///      found at the following link.
///
///      https://hackmd.io/lRZ4mgdrRgOpxZQXqKYlFw?view
///
///      That paper builds on the original YieldSpace paper (YS), "YieldSpace:
///      An Automated Liquidity Provider for Fixed Yield Tokens". It can be
///      found at the following link:
///
///      https://yieldprotocol.com/YieldSpace.pdf
///
///      In these notes, both of these papers will be referenced in
///      abbreviated form: YS and MYS.
///      _______________________________________________________________________
///      # Overview #
///
///      YS introduces the concept of "fyTokens" which conceptualizes a token
///      which redeems for some target asset after a fixed maturity date.
///      We refer to "fyTokens" in this project as "bonds" and readers may also
///      be familiar with them as "principal tokens" from the first implementation
///      of the Element protocol. Typically, the target asset is called "base" as
///      the bond is labelled and normally only traded with that asset, e.g,
///      fyDAI/ptDAI
///
///      As an example, a bond at some point prior to maturity may trade at a
///      value of 0.9090... base and is expected to accrete to a value of 1 base
///      at maturity. A trader who purchases that bond, provided they hold it
///      until maturity, will be guaranteed a rate of return based on the value
///      difference from the time of purchase to maturity. Using the previous
///      figures, 1 - 0.9090.. = 0.0909.. which as a percentage value of the
///      price the bond was initially purchased at is 10%.
///
///      YS envisions a constant function market maker (CFMM) which maintains
///      reserves of bond and base and incorporates time as a function of how
///      these reserves should trade against one another. This formula is
///      commonly referred to as an "invariant" which, generally explained, is a
///      a mathematical rule which must always be upheld and enforces properties
///      on how trading should occur. YS introduces the "constant power sum"
///      invariant which is written as:
///
///        x^(1-t) + y^(1-t) = k
///
///      As written in the YS paper, the curve resembles a hybrid of the
///      constant sum (x + y = k) and the constant product (x * y = k)
///      invariants. The constant sum invariant enforces the property that the
///      spot price will remain fixed regardless of the balances of the reserves
///      in the pools.
///      Conversely, as t approaches 1, the trading curve emulates the constant
///      product invariant which defines the spot prices of both assets such
///      that the reserves of those assets are equal in value.
///      With these properties, arbitrage in such a market functions prices
///      bonds such that they loosely express the accretion of interest over
///      time.
///      However, one important critique of this model is because all base
///      assets are held in reserve, there is effectively zero capital
///      utilisation and liquidity providers would only earn a return from fees
///      laid on bond purchases.
///
///      MYS solves this capital utilisation problem by using reserves of
///      "shares" instead of base. A share is a unit claim to a deposit of
///      base in some interest accruing enterprise *and* the variable interest
///      accrued on that deposit. Examples of this are aDAI or cDAI for which
///      the DAI depositors to the Aave and Compound protocols generate a rate
///      of return over time for lending those deposits to fee-paying borrowers.
///
///      With this, under the MYS model, all deposits of base would be invested
///      in some "vault" (Yield bearing Vault) and the shares given in return
///      for those deposits are held in reserve, thereby collectively accruing
///      variable interest for the pool. This of course modifes the "constant
///      power sum" invariant to incorporate shares as an intermediary pricing
///      mechanic between bonds and base.
///      _______________________________________________________________________
///      # Definitions #
///
///      X, x  :- "X" is the mathematical notation for a base assets, reserves
///               of base are notated as "x"
///
///      Y, y  :- "Y" is the mathematical notation for a bond assets, reserves
///               of bonds are notated as "y"
///
///      Z, z  :- "Z" is the mathematical notation for a share assets, reserves
///                of shares are notated as "z"
///
///      t     :- "t" represents time until to maturity and is normalized such
///               that 0 <= t < 1.
///
///      c     :- "c" is the conversion rate between base and share reserves in
///               a vault. It is expected to increase over time with respect to
///               shares. It is also described as "redemption price" or "share
///               price"
///
///      μ     :- "μ" is typically the initial value of "c" at the beginning of
///               the term which is used as a normalizing constant to accurately
///               account for the accrual of interest of shares in base terms.
///
///      p     :- "p" is defined in context of the invariant relationship of
///               base and bond reserves. This means that as a general principle
///               price is defined as the rate of change between x and y.
///               More simply, if some quantity of x is added to the pool, some
///               quantity of y must leave (or vice-versa). These are denoted as
///               dx and dy and therefore expressed in the equation:
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
///               The definition of p provided in the YS paper is meant to be
///               generalised to illustrate how invariants can be conceived but
///               the most simple example is how the constant product formula
///               expresses p to maintain equal value of reserves of a pool
///
///                 p = y/x
///
///      r     :- "r" is defined in the YS paper in tandem with p but with the
///               added quality that the ratio of bond and base reserves emulate
///               the interest rate for that bond
///
///               r = y/x - 1
///
///               Supposing, bond reserves of 11,000 and base reserves of
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
///      This can be refactored to:
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
///
///      This should illustrate how the pricing formula derives the accrual of
///      interest over the duration t in YS. Also to note that t and the interest
///      amounts do not necessarily have to be derived around annual time periods.
///      t can be normalized to any time period.
///      The constant power sum formula is derived from p in the appendix of the
///      YS paper.
///
///      _______________________________________________________________________
///      # The Modified YieldSpace invariant #
///
///      As stated before, MYS conceptualizes greater capital utilisation whilst
///      still providing the same bond market mechanics as derived in YS. The
///      conceptual difference to understand is that the invariant must derive
///      the same bond/base relationship through the redemption value (c) of
///      shares to base. This makes the math a bit more convoluted but the
///      underlying principle remains the same.
///
///      MYS expresses the base reserves in a virtual manner where the redemption
///      price and the number of shares held in reserve are computed:
///
///        x = cz
///
///      As c monotonically increases over time, the amount of bond reserves
///      held by the contract should increase over time also. Consequential to
///      this is that the reserves of shares and bonds in this implementation
///      must be priced in respect of the base asset.
///
///      This changes the YS implementation of how r was derived from:
///
///        1 + r = y / x
///
///      to:
///
///        1 + r = y / (µ * z) = (c * y) / (µ * x)
///
///      µ, as mentioned before is typically c at market initialisation (t = 0)
///      and so when considering the interest rate of the bonds,
///
///        µ = 1.1
///        z = 90.909090... (100/µ)
///        y = 110
///
///        r = (110 / 1.1 * 90.909090) - 1 = 0.1 = 10%
///
///      Presume that some time has passed and now c and µ have diverged:
///
///        c = 1.12
///        x = c * z = 109.9090
///        r = (1.12 * 110) / (1.1 * 109.909090) - 1 = 0.1 = 10%
///
///      This exemplifies how we can use shares as a mechanism for pricing
///      interest.
///      As was done in YS, MYS combines the interest rate and reserve
///      pricing formulas to construct the invariant. Knowing that the price
///      of bonds in terms of base is found as:
///
///        p = -1 / (dy / dx)
///
///      Then we can derive r using p like:
///
///        r = (1 / p)^(1 / t) - 1 = (1 / (-1 / (dy / dx)))^(1 / t) - 1
///
///      Then deriving the invariant we build the equation:
///
///        (-dy / dx) = ((c * y) / (µ * x))^t
///
///      Which evaluates to:
///
///        (c / µ) * (µ * z)^(1 - t) + y^(1 - t) = C
///
///      This formula becomes the basis of how trade calculations are derived.
///      If more illustration is needed, the MYS trading curve has been graphed
///      at this link which may help for visualisation:
///
///        https://www.desmos.com/calculator/vfrzlsopsb
///
///      There is one important consideration to note in these formulas
///
///      TODO Note how the bondReserveAdjustment works
///
///      _______________________________________________________________________
///      # The Modified YieldSpace trades #
///
///      The code as expressed in this library defines 4 trading actions:
///
///      - bondsInGivenSharesOut
///        Δy = (C - (c / µ) * (µ * (z - dz))^(1 - t))^(1 / (1 - t))) - y
///      - bondsOutGivenSharesIn
///        Δy = y - (C - (c / µ) * (µ * (z + dz))^(1 - t))^(1 / (1 - t)))
///      - sharesInGivenBondsOut
///        Δz = (((C - (y - dy)^(1 - t)) / (c / µ))^(1 / (1 - t)) / µ) - z
///      - sharesOutGivenBondsIn
///        Δz = z - (((C - (y + Δy)^(1 - t)) / c/μ )^(1 / (1 - t)) / µ)
///
///        NOTE: C = (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
///
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
    /// @param _isShareIn determines if the input is bond or shares
    /// @return Amount of shares/bonds
    function calculateOutGivenIn(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _bondReserveAdjustment,
        uint256 _amountIn,
        uint256 _stretchedTimeElapsed,
        uint256 _c,
        uint256 _mu,
        bool _isShareIn
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

        if (_isShareIn) {
            // (mu * (shareReserves + amountIn))^(1 - tau)
            _shareReserves = _mu.mulDown(_shareReserves.add(_amountIn)).pow(
                _stretchedTimeElapsed
            );
            // (c / mu) * (mu * (shareReserves + amountIn))^(1 - tau)
            _shareReserves = cDivMu.mulDown(_shareReserves);
            // NOTE: k - shareReserves >= 0 to avoid a complex number
            // ((c / mu) * (mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (c / mu) * (mu * (shareReserves + amountIn))^(1 - tau))^(1 / (1 - tau)))
            uint256 newBondReserves = k.sub(_shareReserves).pow(
                FixedPointMath.ONE_18.divUp(_stretchedTimeElapsed)
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
                FixedPointMath.ONE_18.divUp(_stretchedTimeElapsed)
            );
            // (((mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (bondReserves + bondIn)^(1 - tau) ) / (c / mu))^(1 / (1 - tau))) / mu
            newShareReserves = newShareReserves.divDown(_mu);
            // NOTE: shareReserves - sharesOut >= 0, but I think avoiding a complex number in the step above ensures this never happens
            // sharesOut = shareReserves - (((c / mu) * (mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (bondReserves + bondIn)^(1 - tau) ) / (c / mu))^(1 / (1 - tau))) / mu
            return _shareReserves.sub(newShareReserves);
        }
    }

    /// @dev Calculates the amount of an asset that will be received given a
    ///      specified amount of the other asset given the current AMM reserves.
    /// @dev _isShareOut = True isn't used in the current implementation,
    ///      but is included for completeness
    /// @param _shareReserves yield bearing vault shares reserve amount, unit is shares
    /// @param _bondReserves bond reserves amount, unit is the face value in underlying
    /// @param _bondReserveAdjustment An optional adjustment to the reserve which MUST have units of underlying.
    /// @param _amountOut amount to be received, if bonds in the unit is underlying, if shares in the unit is shares
    /// @param _stretchedTimeElapsed Amount of time elapsed since term start
    /// @param _c price of shares in terms of their base
    /// @param _mu Normalization factor -- starts as c at initialization
    /// @param _isShareOut determines if the output is bond or shares
    /// @return Amount of shares/bonds
    function calculateInGivenOut(
        uint256 _shareReserves,
        uint256 _bondReserves,
        uint256 _bondReserveAdjustment,
        uint256 _amountOut,
        uint256 _stretchedTimeElapsed,
        uint256 _c,
        uint256 _mu,
        bool _isShareOut
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

        if (_isShareOut) {
            // (mu * (shareReserves - amountOut))^(1 - tau)
            _shareReserves = _mu.mulDown(_shareReserves.sub(_amountOut)).pow(
                _stretchedTimeElapsed
            );
            // (c / mu) * (mu * (shareReserves - amountOut))^(1 - tau)
            _shareReserves = cDivMu.mulDown(_shareReserves);
            // NOTE: k - shareReserves >= 0 to avoid a complex number
            // ((c / mu) * (mu * shareReserves)^(1 - tau) + bondReserves^(1 - tau) - (c / mu) * (mu*(shareReserves - amountOut))^(1 - tau))^(1 / (1 - tau)))
            uint256 newBondReserves = k.sub(_shareReserves).pow(
                FixedPointMath.ONE_18.divUp(_stretchedTimeElapsed)
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
                FixedPointMath.ONE_18.divUp(_stretchedTimeElapsed)
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
