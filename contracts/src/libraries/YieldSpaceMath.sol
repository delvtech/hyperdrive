/// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { FixedPointMath } from "./FixedPointMath.sol";

/// @author DELV
/// @title YieldSpaceMath
/// @notice Math for the YieldSpace pricing model.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
///
/// @dev It is advised for developers to attain the pre-requisite knowledge
///      of how this implementation works on the mathematical level. This
///      excerpt attempts to document this pre-requisite knowledge explaining
///      the underpinning mathematical concepts in an understandable manner and
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
///      utilization and liquidity providers would only earn a return from fees
///      laid on bond purchases.
///
///      MYS solves this capital utilization problem by using reserves of
///      "shares" instead of base. A share is a unit claim to a deposit of
///      base in some interest accruing enterprise *and* the variable interest
///      accrued on that deposit. Examples of this are aDAI or cDAI for which
///      the DAI depositors to the Aave and Compound protocols generate a rate
///      of return over time for lending those deposits to fee-paying borrowers.
///
///      With this, under the MYS model, all deposits of base would be invested
///      in some "vault" (Yield bearing Vault) and the shares given in return
///      for those deposits are held in reserve, thereby collectively accruing
///      variable interest for the pool. This of course modifies the "constant
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
///               generalized to illustrate how invariants can be conceived but
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
///      In YieldSpace, it is desired that the interest rate is a function of
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
///      As stated before, MYS conceptualizes greater capital utilization whilst
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
///      µ, as mentioned before is typically c at market initialization (t = 0)
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
///        (c / µ) * (µ * z)^(1 - t) + y^(1 - t) = k
///
///      This formula becomes the basis of how trade calculations are derived.
///      If more illustration is needed, the MYS trading curve has been graphed
///      at this link which may help for visualization:
///
///        https://www.desmos.com/calculator/vfrzlsopsb
///
library YieldSpaceMath {
    using FixedPointMath for uint256;

    /// Calculates the amount of bonds a user must provide the pool to receive
    /// a specified amount of shares
    /// @param z Amount of share reserves in the pool
    /// @param y Amount of bond reserves in the pool
    /// @param dz Amount of shares user wants to receive
    /// @param t Amount of time elapsed since term start
    /// @param c Conversion rate between base and shares
    /// @param mu Interest normalization factor for shares
    function calculateBondsInGivenSharesOut(
        uint256 z,
        uint256 y,
        uint256 dz,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256) {
        // c/µ
        uint256 cDivMu = c.divDown(mu);
        // (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
        uint256 k = _modifiedYieldSpaceConstant(cDivMu, mu, z, t, y);
        // (µ * (z - dz))^(1 - t)
        z = mu.mulDown(z.sub(dz)).pow(t);
        // (c / µ) * (µ * (z - dz))^(1 - t)
        z = cDivMu.mulDown(z);
        // ((c / µ) * (µ * z)^(1 - t) + y^(1 - t) - (c / µ) * (µ * (z - dz))^(1 - t))^(1 / (1 - t)))
        uint256 _y = k.sub(z).pow(FixedPointMath.ONE_18.divUp(t));
        // Δy = ((c / µ) * (µ * z)^(1 - t) + y^(1 - t) - (c / µ) * (µ * (z - dz))^(1 - t))^(1 / (1 - t))) - y
        return _y.sub(y);
    }

    /// Calculates the amount of bonds a user will receive from the pool by
    /// providing a specified amount of shares
    /// @param z Amount of share reserves in the pool
    /// @param y Amount of bond reserves in the pool
    /// @param dz Amount of shares user wants to provide
    /// @param t Amount of time elapsed since term start
    /// @param c Conversion rate between base and shares
    /// @param mu Interest normalization factor for shares
    function calculateBondsOutGivenSharesIn(
        uint256 z,
        uint256 y,
        uint256 dz,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256) {
        // c/µ
        uint256 cDivMu = c.divDown(mu);
        // (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
        uint256 k = _modifiedYieldSpaceConstant(cDivMu, mu, z, t, y);
        // (µ * (z + dz))^(1 - t)
        z = mu.mulDown(z.add(dz)).pow(t);
        // (c / µ) * (µ * (z + dz))^(1 - t)
        z = cDivMu.mulDown(z);
        // ((c / µ) * (µ * z)^(1 - t) + y^(1 - t) - (c / µ) * (µ * (z + dz))^(1 - t))^(1 / (1 - t)))
        uint256 _y = k.sub(z).pow(FixedPointMath.ONE_18.divUp(t));
        // Δy = y - ((c / µ) * (µ * z)^(1 - t) + y^(1 - t) - (c / µ) * (µ * (z + dz))^(1 - t))^(1 / (1 - t)))
        return y.sub(_y);
    }

    /// Calculates the amount of shares a user must provide the pool to receive
    /// a specified amount of bonds
    /// @param z Amount of share reserves in the pool
    /// @param y Amount of bond reserves in the pool
    /// @param dy Amount of bonds user wants to provide
    /// @param t Amount of time elapsed since term start
    /// @param c Conversion rate between base and shares
    /// @param mu Interest normalization factor for shares
    function calculateSharesInGivenBondsOut(
        uint256 z,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256) {
        // c/µ
        uint256 cDivMu = c.divDown(mu);
        // (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
        uint256 k = _modifiedYieldSpaceConstant(cDivMu, mu, z, t, y);
        // (y - dy)^(1 - t)
        y = y.sub(dy).pow(t);
        // (((µ * z)^(1 - t) + y^(1 - t) - (y - dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))
        uint256 _z = k.sub(y).divDown(cDivMu).pow(
            FixedPointMath.ONE_18.divUp(t)
        );
        // (((µ * z)^(1 - t) + y^(1 - t) - (y - dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))) / µ
        _z = _z.divDown(mu);
        // Δz = ((((c / µ) * (µ * z)^(1 - t) + y^(1 - t) - (y - dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))) / µ) - z
        return _z.sub(z);
    }

    /// Calculates the amount of shares a user will receive from the pool by
    /// providing a specified amount of bonds
    /// @param z Amount of share reserves in the pool
    /// @param y Amount of bond reserves in the pool
    /// @param dy Amount of bonds user wants to provide
    /// @param t Amount of time elapsed since term start
    /// @param c Conversion rate between base and shares
    /// @param mu Interest normalization factor for shares
    function calculateSharesOutGivenBondsIn(
        uint256 z,
        uint256 y,
        uint256 dy,
        uint256 t,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256) {
        // c/µ
        uint256 cDivMu = c.divDown(mu);
        // (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
        uint256 k = _modifiedYieldSpaceConstant(cDivMu, mu, z, t, y);
        // (y + dy)^(1 - t)
        y = y.add(dy).pow(t);
        // (((µ * z)^(1 - t) + y^(1 - t) - (y + dy)^(1 - t)) / (c / µ))^(1 / (1 - t)))
        uint256 _z = k.sub(y).divDown(cDivMu).pow(
            FixedPointMath.ONE_18.divUp(t)
        );
        // (((µ * z)^(1 - t) + y^(1 - t) - (y + dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))) / µ
        _z = _z.divDown(mu);
        // Δz = z - (((c / µ) * (µ * z)^(1 - t) + y^(1 - t) - (y + dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))) / µ
        return z.sub(_z);
    }

    /// @dev Helper function to derive invariant constant C
    /// @param cDivMu Normalized price of shares in terms of base
    /// @param mu Interest normalization factor for shares
    /// returns C The modified YieldSpace Constant
    /// @param z Amount of share reserves in the pool
    /// @param t Amount of time elapsed since term start
    /// @param y Amount of bond reserves in the pool
    function _modifiedYieldSpaceConstant(
        uint256 cDivMu,
        uint256 mu,
        uint256 z,
        uint256 t,
        uint256 y
    ) private pure returns (uint256) {
        /// k = (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
        return cDivMu.mulDown(mu.mulDown(z).pow(t)).add(y.pow(t));
    }
}
