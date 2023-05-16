import "./CVLMath.spec";

methods {
    /// FixedPoint Math
    /// @dev Updates a weighted average by adding or removing a weighted delta.
    function _.updateWeightedAverage(uint256,uint256,uint256,uint256,bool) internal library => NONDET;
    /// @dev Once CERT-2050 is fixed, we could switch to custom summary
        //function _.updateWeightedAverage(uint256 avg, uint256 totW, uint256 del, uint256 delW ,bool isAdd) 
        //    internal library => CVLUpdateWeightedAverage(avg, totW, del, delW, isAdd) expect uint256;
    function _.pow(uint256 x, uint256 y) internal library => CVLPow(x, y) expect uint256;
    function _.exp(int256) internal library => NONDET;
    function _.ln(int256) internal library => NONDET;
    function _.mulDivDown(uint256 x, uint256 y, uint256 d) internal library => mulDivDownAbstractPlus(x, y, d) expect uint256;
    function _.mulDivUp(uint256 x, uint256 y, uint256 d) internal library => mulDivUpAbstractPlus(x, y, d) expect uint256;

    /// YieldSpace (YS) Math
    /// @dev Calculates the amount of bonds a user must provide the pool to receive
    /// a specified amount of shares
    function _.calculateBondsInGivenSharesOut(uint256 z, uint256 y, uint256 dz, uint256 t, uint256 c, uint256 mu)
        internal library => CVLBondsInGivenSharesOut(z,y,dz,t,c,mu) expect uint256;
    
    /// @dev Calculates the amount of bonds a user will receive from the pool by
    /// providing a specified amount of shares
    function _.calculateBondsOutGivenSharesIn(uint256 z, uint256 y, uint256 dz, uint256 t, uint256 c, uint256 mu)
        internal library => CVLBondsOutGivenSharesIn(z,y,dz,t,c,mu) expect uint256;
    
    /// @dev Calculates the amount of shares a user must provide the pool to receive
    /// a specified amount of bonds
    function _.calculateSharesInGivenBondsOut(uint256 z, uint256 y, uint256 dy, uint256 t, uint256 c, uint256 mu)
        internal library => CVLSharesInGivenBondsOut(z,y,dy,t,c,mu) expect uint256; 
    
    /// @dev Calculates the amount of shares a user will receive from the pool by
    /// providing a specified amount of bonds
    function _.calculateSharesOutGivenBondsIn(uint256 z, uint256 y, uint256 dy, uint256 t, uint256 c, uint256 mu)
        internal library => CVLSharesOutGivenBondsIn(z,y,dy,t,c,mu) expect uint256;

    /// Hyperdrive (HD) Math
    /// @dev Calculates the base volume of an open trade given the base amount, the bond amount, and the time remaining.
    function _.calculateBaseVolume(uint256 base, uint256 bond ,uint256 time) internal library 
        => ghostCalculateBaseVolume(base, bond, time) expect uint256;
    
    /// @dev Calculates the spot price without slippage of bonds in terms of shares.
    function _.calculateSpotPrice(uint256 shares, uint256 bonds, uint256 initPrice, uint256 normTime, uint256 timeSt) internal library 
        => ghostCalculateSpotPrice(shares, bonds, initPrice, normTime, timeSt) expect uint256;
    
    /// @dev Calculates the APR from the pool's reserves.
    function _.calculateAPRFromReserves(uint256 shares, uint256 bonds, uint256 initPrice, uint256 dur, uint256 timeSt) internal library
        => ghostCalculateAPRFromReserves(shares, bonds, initPrice, dur, timeSt) expect uint256;
    
    /// @dev Calculates the initial bond reserves assuming that the initial LP
    function _.calculateInitialBondReserves(uint256 shares, uint256 price, uint256 initPrice, uint256 APR, uint256 dur, uint256 timeSt) internal library 
        => ghostCalculateInitialBondReserves(shares, price, initPrice, APR, dur, timeSt) expect uint256;
    
    /// @dev Calculates the present value LPs capital in the pool.
    function _.calculatePresentValue(HyperdriveMath.PresentValueParams memory) internal library => NONDET; 
    
    /// @dev Calculates the interest in shares earned by a short position
    function _.calculateShortInterest(uint256 bond, uint256 openPrice, uint256 closePrice, uint256 price) internal library 
        => ghostCalculateShortInterest(bond, openPrice, closePrice, price) expect uint256;
    
    /// @dev Calculates the proceeds in shares of closing a short position.
    function _.calculateShortProceeds(uint256 bond, uint256 share, uint256 openPrice, uint256 closePrice, uint256 price) internal library 
        => ghostCalculateShortProceeds(bond, share, openPrice, closePrice, price) expect uint256;
}

/// Ghost implementations of FixedPoint Math
function CVLUpdateWeightedAverage(uint256 avg, uint256 totW, uint256 del, uint256 delW, bool isAdd) returns uint256 {
    if(isAdd) {return CVLUpdateWeightedAverage_add(avg, totW, del, delW);}
    else {return CVLUpdateWeightedAverage_sub(avg, totW, del, delW);}
}

function CVLUpdateWeightedAverage_add(uint256 avg, uint256 totW, uint256 del, uint256 delW) returns uint256 {
    if(delW == 0) {return require_uint256(avg * ONE18());}
    return require_uint256(to_mathint(avg) + ghostWeightedAverage(del-avg,delW,totW));
}

function CVLUpdateWeightedAverage_sub(uint256 avg, uint256 totW, uint256 del, uint256 delW) returns uint256 {
    if(totW == delW) {return 0;}
    else {
        require(totW > delW);
        if(delW == 0) {return require_uint256(avg * ONE18());}
        return require_uint256(to_mathint(avg) + ghostWeightedAverage(del-avg,0-delW,totW));
    }
}

ghost ghostWeightedAverage(mathint, mathint, mathint) returns mathint {
    axiom forall mathint x. forall mathint y. forall mathint z.
        weightedAverage(x,y,z, ghostWeightedAverage(x,y,z));
}

/// Ghost implementations of Hyperdrive Math
ghost ghostCalculateBaseVolume(uint256,uint256,uint256) returns uint256 {
    axiom forall uint256 x. forall uint256 y. 
        forall uint256 z. forall uint256 w. 
            _monotonicallyIncreasing(x, y , ghostCalculateBaseVolume(x,z,w), ghostCalculateBaseVolume(y,z,w));
}

ghost ghostCalculateSpotPrice(uint256,uint256,uint256,uint256,uint256) returns uint256;
ghost ghostCalculateAPRFromReserves(uint256,uint256,uint256,uint256,uint256) returns uint256;
ghost ghostCalculateInitialBondReserves(uint256,uint256,uint256,uint256,uint256,uint256) returns uint256;
ghost ghostCalculateShortInterest(uint256,uint256,uint256,uint256) returns uint256;
ghost ghostCalculateShortProceeds(uint256,uint256,uint256,uint256,uint256) returns uint256;

/* =========================================
 ---------- YieldSpace Math summaries -----
=========================================== */
/// @idea Should we use assert_uint256 or require_uint256 ?

/// @dev a CVL require equivalent to the YieldSpace invariant:
/// For every two pairs of bonds-shares reserves state (z1,y1) and (z2,y2) the 
/// equality below must hold, where:
/*
* z1 - share reserves 1
* z2 - share reserves 2
* y1 - bond reserves 1
* y2 - bond reserves 2
* mu - initial share rate
* c - current share rate (redemption price)
* t - (normalized) time until maturity (0 <= t < 1)
*/
function YSInvariant(
    uint256 z1,
    uint256 z2,
    uint256 y1, 
    uint256 y2, 
    uint256 mu,
    uint256 c, 
    uint256 t) returns bool {
    uint256 tp = require_uint256(ONE18() - t); /// t' = 1 - t;
    return c * ONE18() * (CVLPow(z1, tp) - CVLPow(z2, tp)) ==
        to_mathint(CVLPow(mu, t)) * (CVLPow(y2, tp) - CVLPow(y1, tp));
}

ghost uint256 yp;
ghost uint256 zp;
ghost uint256 tp;

/*
- bondsInGivenSharesOut
    Δy = (k - (c / µ) * (µ * (z - dz))^(1 - t))^(1 / (1 - t))) - y
*/
function CVLBondsInGivenSharesOut(uint256 z, uint256 y, uint256 dz, uint256 t, uint256 c, uint256 mu) returns uint256 {
    havoc yp; havoc zp; havoc tp;
    require zp == require_uint256(z - dz);
    require tp == require_uint256(ONE18() - t);
    require YSInvariant(z, zp, y, yp, mu, c, tp);
    return require_uint256(yp - y);
}

/*
- bondsOutGivenSharesIn
    Δy = y - (k - (c / µ) * (µ * (z + dz))^(1 - t))^(1 / (1 - t)))
*/
function CVLBondsOutGivenSharesIn(uint256 z, uint256 y, uint256 dz, uint256 t, uint256 c, uint256 mu) returns uint256 {
    havoc yp; havoc zp; havoc tp;
    require zp = require_uint256(z + dz);
    require tp = require_uint256(ONE18() - t);
    require YSInvariant(z, zp, y, yp, mu, c, tp);
    return require_uint256(y - yp);
}

/*
- sharesInGivenBondsOut
    Δz = (((k - (y - dy)^(1 - t)) / (c / µ))^(1 / (1 - t)) / µ) - z
*/
function CVLSharesInGivenBondsOut(uint256 z, uint256 y, uint256 dy, uint256 t, uint256 c, uint256 mu) returns uint256 {
    havoc yp; havoc zp; havoc tp;
    require yp = require_uint256(y - dy);
    require tp = require_uint256(ONE18() - t);
    require YSInvariant(z, zp, y, yp, mu, c, tp);
    return require_uint256(zp - z);
}

/*
- sharesOutGivenBondsIn
    Δz = z - (((k - (y + Δy)^(1 - t)) / c/μ )^(1 / (1 - t)) / µ)
*/
function CVLSharesOutGivenBondsIn(uint256 z, uint256 y, uint256 dy, uint256 t, uint256 c, uint256 mu) returns uint256 {
    havoc yp; havoc zp; havoc tp;
    require yp = require_uint256(y + dy);
    require tp = require_uint256(ONE18() - t);
    require YSInvariant(z, zp, y, yp, mu, c, tp);
    return require_uint256(z - zp);
}
