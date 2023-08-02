import "./CVLMath.spec";

methods {
    /// FixedPoint Math
    /// @dev Updates a weighted average by adding or removing a weighted delta.
    function _.updateWeightedAverage(uint256 avg, uint256 totW, uint256 del, uint256 delW ,bool isAdd) internal 
        => CVLUpdateWeightedAverage(avg, totW, del, delW, isAdd) expect uint256;
    function _.pow(uint256 x, uint256 y) internal => CVLPow(x, y) expect uint256;
    function _.exp(int256) internal => NONDET;
    function _.ln(int256) internal => NONDET;
    function _.mulDivDown(uint256 x, uint256 y, uint256 d) internal => mulDivDownAbstractPlus(x, y, d) expect uint256;
    function _.mulDivUp(uint256 x, uint256 y, uint256 d) internal => mulDivUpAbstractPlus(x, y, d) expect uint256;

    /// YieldSpace (YS) Math
    /// @dev Calculates the amount of bonds a user must provide the pool to receive
    /// a specified amount of shares
    function _.calculateBondsInGivenSharesOut(uint256 z, uint256 y, uint256 dz, uint256 t, uint256 c, uint256 mu)
        internal => CVLBondsInGivenSharesOut(z,y,dz,t,c,mu) expect uint256;
    
    /// @dev Calculates the amount of bonds a user will receive from the pool by
    /// providing a specified amount of shares
    // function _.calculateBondsOutGivenSharesIn(uint256 z, uint256 y, uint256 dz, uint256 t, uint256 c, uint256 mu)
    //     internal => CVLBondsOutGivenSharesIn(z,y,dz,t,c,mu) expect uint256;
    
    /// @dev Calculates the amount of shares a user must provide the pool to receive
    /// a specified amount of bonds
    function _.calculateSharesInGivenBondsOut(uint256 z, uint256 y, uint256 dy, uint256 t, uint256 c, uint256 mu)
        internal => CVLSharesInGivenBondsOut(z,y,dy,t,c,mu) expect uint256; 
    
    /// @dev Calculates the amount of shares a user will receive from the pool by
    /// providing a specified amount of bonds
    function _.calculateSharesOutGivenBondsIn(uint256 z, uint256 y, uint256 dy, uint256 t, uint256 c, uint256 mu)
        internal => CVLSharesOutGivenBondsIn(z,y,dy,t,c,mu) expect uint256;

    /// Hyperdrive (HD) Math
    /// @dev Calculates the base volume of an open trade given the base amount, the bond amount, and the time remaining.
    function _.calculateBaseVolume(uint256 base, uint256 bond ,uint256 time) internal 
        => ghostCalculateBaseVolume(base, bond, time) expect uint256;
    
    /// @dev Calculates the spot price without slippage of bonds in terms of shares.
    //function _.calculateSpotPrice(uint256 shares, uint256 bonds, uint256 initPrice, uint256 normTime, uint256 timeSt) internal
    //    => CVLCalculateSpotPrice(shares, bonds, initPrice, normTime, timeSt) expect uint256;
    function _.calculateSpotPrice(uint256 shares, uint256 bonds, uint256 initPrice, uint256 normTime, uint256 timeSt) internal => NONDET;
    
    /// @dev Calculates the APR from the pool's reserves.
    function _.calculateAPRFromReserves(uint256 shares, uint256 bonds, uint256 initPrice, uint256 dur, uint256 timeSt) internal
        => ghostCalculateAPRFromReserves(shares, bonds, initPrice, dur, timeSt) expect uint256;
    
    /// @dev Calculates the initial bond reserves assuming that the initial LP
    function _.calculateInitialBondReserves(uint256 shares, uint256 price, uint256 initPrice, uint256 APR, uint256 dur, uint256 timeSt) internal 
        => ghostCalculateInitialBondReserves(shares, price, initPrice, APR, dur, timeSt) expect uint256;
    
    /// @dev Calculates the present value LPs capital in the pool.
    /// @notice Replacement of original HyperdriveMath function with Mock.
    //function HyperdriveMath.calculatePresentValue(HyperdriveMath.PresentValueParams memory params) internal returns (uint256) => CVLCalculatePresentValue(params);
    function _._calculatePresentValue(
        uint256 z, uint256 y, uint256 c, uint256 mu, uint256 ts,
        uint256 ol, uint256 tavg_L, uint256 os, uint256 tavg_S, uint256 vol) internal => 
        CVLCalculatePresentValue(z,y,c,mu,ts,ol,tavg_L,os,tavg_S,vol) expect uint256;
    
    /// @dev Calculates the interest in shares earned by a short position
    function _.calculateShortInterest(uint256 bond, uint256 openPrice, uint256 closePrice, uint256 price) internal 
        => ghostCalculateShortInterest(bond, openPrice, closePrice, price) expect uint256;
    
    /// @dev Calculates the proceeds in shares of closing a short position.
    // function _.calculateShortProceeds(uint256 bond, uint256 share, uint256 openPrice, uint256 closePrice, uint256 price) internal 
    //    => CVLCalculateShortProceeds(bond, share, openPrice, closePrice, price) expect uint256;
}

/// Ghost implementations of FixedPoint Math
function CVLUpdateWeightedAverage(uint256 avg, uint256 totW, uint256 del, uint256 delW, bool isAdd) returns uint256 {
    if(isAdd) {return CVLUpdateWeightedAverage_add(avg, totW, del, delW);}
    else {return CVLUpdateWeightedAverage_sub(avg, totW, del, delW);}
}

function CVLUpdateWeightedAverage_add(uint256 avg, uint256 totW, uint256 del, uint256 delW) returns uint256 {
    if(delW == 0) {return require_uint256(avg);}
    return require_uint256(to_mathint(avg) + ghostWeightedAverage(del-avg,delW,totW));
}

function CVLUpdateWeightedAverage_sub(uint256 avg, uint256 totW, uint256 del, uint256 delW) returns uint256 {
    if(totW == delW) {return 0;}
    else {
        require(totW > delW);
        if(delW == 0) {return require_uint256(avg);}
        return require_uint256(to_mathint(avg) + ghostWeightedAverage(del-avg,0-delW,totW));
    }
}

/// Summary for the updateWeightedAverage.
/// @notice Note that due to rounding errors, the summary is not 100% correct, so deviations of the order of 1
/// are possible in the real function.
ghost ghostWeightedAverage(mathint, mathint, mathint) returns mathint {
    axiom forall mathint x. forall mathint y. forall mathint z.
        weightedAverage(x,y,z, ghostWeightedAverage(x,y,z));
    axiom forall mathint x. forall mathint y. forall mathint z.
        y != 0 && x != 0 => ghostWeightedAverage(x,y,z) != 0;

    //axiom forall mathint x. forall mathint y. forall mathint z.
    //    (abs(y) < abs(z) => abs(ghostWeightedAverage(x,y,z)) <= abs(x)/2) &&
    //    (abs(y) >= abs(z) => abs(ghostWeightedAverage(x,y,z)) >= abs(x)/2);
}

/// Ghost implementations of Hyperdrive Math
ghost ghostCalculateBaseVolume(uint256,uint256,uint256) returns uint256 {
    axiom forall uint256 x. forall uint256 y. forall uint256 z.
        min(to_mathint(ghostCalculateBaseVolume(x,y,z)), to_mathint(y)) <= to_mathint(x)
        &&
        max(to_mathint(ghostCalculateBaseVolume(x,y,z)), to_mathint(y)) >= to_mathint(x); 
    
    axiom forall uint256 x. forall uint256 y. forall uint256 z.
        z == ONE18() => ghostCalculateBaseVolume(x,y,z) == x;
}

ghost ghostCalculateAPRFromReserves(uint256,uint256,uint256,uint256,uint256) returns uint256;
ghost ghostCalculateInitialBondReserves(uint256,uint256,uint256,uint256,uint256,uint256) returns uint256;
ghost ghostCalculateShortInterest(uint256,uint256,uint256,uint256) returns uint256;

/// Summary for calculateShortProceeds
function CVLCalculateShortProceeds(uint256 amount, uint256 shareDelta, uint256 openPrice, uint256 closePrice, uint256 price) returns uint256 {
    if(closePrice == price) {
        uint256 bondFactor = divDownWad(amount, openPrice);
        if (bondFactor > shareDelta) {
            return require_uint256(bondFactor - shareDelta);
        }
        else {
            return 0;
        }
    }
    else {
        uint256 bondFactor = mulDivDownAbstractPlus(amount, closePrice, mulUpWad(openPrice, price));
        if (bondFactor > shareDelta) {
            return require_uint256(bondFactor - shareDelta);
        }
        else {
            return 0;
        }
    }
}

/* =========================================
 ---------- Hyperdrive Math summaries ------
============================================ */

/// Present value summary : CVL summary for calculatePresentValue() 
ghost mathint shareReservesDelta;
ghost mathint netCurveTrade;
ghost mathint netFlatTrade;

function CVLCalculatePresentValue(
        uint256 shareReserves,
        uint256 bondReserves,
        uint256 sharePrice,
        uint256 initialSharePrice,
        uint256 timeStretch,
        uint256 longsOutstanding,
        uint256 longAverageTimeRemaining,
        uint256 shortsOutstanding,
        uint256 shortAverageTimeRemaining,
        uint256 shortBaseVolume)
    returns uint256
{
    mathint z = to_mathint(shareReserves);
    mathint y = to_mathint(bondReserves);
    mathint c = to_mathint(sharePrice);
    mathint mu = to_mathint(initialSharePrice);
    mathint ts = to_mathint(timeStretch);
    mathint longOut = to_mathint(longsOutstanding);
    mathint timeAvg_L = to_mathint(longAverageTimeRemaining);
    mathint shortOut = to_mathint(shortsOutstanding);
    mathint timeAvg_S = to_mathint(shortAverageTimeRemaining);
    mathint vs = to_mathint(shortBaseVolume);

    require c !=0;

    //mathint netCurveTrade = (longOut*timeAvg_L)/ONE18() - (shortOut*timeAvg_S)/ONE18();
    //mathint netFlatTrade = (shortOut*(ONE18() - ts))/c - (longOut*(ONE18() - ts))/c; 
    havoc shareReservesDelta;
    havoc netCurveTrade;
    havoc netFlatTrade;

    require 0 <= netCurveTrade + shortOut && netCurveTrade <= longOut;
    require 0 <= longOut + netFlatTrade * c && netFlatTrade * c <= shortOut;

    if(netCurveTrade > 0) {
        shareReservesDelta = PositiveNetCurveBranch(z,y,netCurveTrade,ts,c,mu);
    }
    else {
        shareReservesDelta = NegativeNetCurveBranch(z,y,netCurveTrade,ts,c,mu);
    }

    /// @Note: unverified assumption
    require abs(shareReservesDelta) <= z;

    return require_uint256(z + netFlatTrade + shareReservesDelta);
}

ghost PositiveNetCurveBranch(mathint,mathint,mathint,mathint,mathint,mathint) returns mathint;
ghost NegativeNetCurveBranch(mathint,mathint,mathint,mathint,mathint,mathint) returns mathint;

/* =========================================
 ---------- YieldSpace Math summaries ------
============================================ */
/// @idea Should we use assert_uint256 or require_uint256 ?

/// a CVL require equivalent to the YieldSpace invariant:
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
    uint256 t
) returns bool {
    uint256 tpp = require_uint256(ONE18() - t); /// t' = 1 - t;
    return c * ONE18() * (CVLPow(z1, tpp) - CVLPow(z2, tpp)) ==
        to_mathint(CVLPow(mu, t)) * (CVLPow(y2, tpp) - CVLPow(y1, tpp));
}

ghost uint256 yp;
ghost uint256 zp;
ghost uint256 tp;

/// YS Math ghosts
ghost BondsInSharesOut(uint256,uint256,uint256,uint256,uint256,uint256) returns uint256;
ghost BondsOutSharesIn(uint256,uint256,uint256,uint256,uint256,uint256) returns uint256;
ghost SharesInBondsOut(uint256,uint256,uint256,uint256,uint256,uint256) returns uint256;
ghost SharesOutBondsIn(uint256,uint256,uint256,uint256,uint256,uint256) returns uint256;

/*
- bondsInGivenSharesOut
    Δy = (k - (c / µ) * (µ * (z - dz))^(1 - t))^(1 / (1 - t))) - y
*/
function CVLBondsInGivenSharesOut(uint256 z, uint256 y, uint256 dz, uint256 t, uint256 c, uint256 mu) returns uint256 {
    zp = require_uint256(z - dz);
    tp = require_uint256(ONE18() - t);
    yp = BondsInSharesOut(z,y,dz,t,c,mu);
    require YSInvariant(z, zp, y, yp, mu, c, tp);
    return require_uint256(yp - y);
}

/*
- bondsOutGivenSharesIn
    Δy = y - (k - (c / µ) * (µ * (z + dz))^(1 - t))^(1 / (1 - t)))
*/
function CVLBondsOutGivenSharesIn(uint256 z, uint256 y, uint256 dz, uint256 t, uint256 c, uint256 mu) returns uint256 {
    zp = require_uint256(z + dz);
    tp = require_uint256(ONE18() - t);
    yp = BondsOutSharesIn(z,y,dz,t,c,mu);
    require YSInvariant(z, zp, y, yp, mu, c, tp);
    return require_uint256(y - yp);
}

/*
- sharesInGivenBondsOut
    Δz = (((k - (y - dy)^(1 - t)) / (c / µ))^(1 / (1 - t)) / µ) - z
*/
function CVLSharesInGivenBondsOut(uint256 z, uint256 y, uint256 dy, uint256 t, uint256 c, uint256 mu) returns uint256 {
    yp = require_uint256(y - dy);
    tp = require_uint256(ONE18() - t);
    zp = SharesInBondsOut(z,y,dy,t,c,mu);
    require YSInvariant(z, zp, y, yp, mu, c, tp);
    return require_uint256(zp - z);
}

/*
- sharesOutGivenBondsIn
    Δz = z - (((k - (y + Δy)^(1 - t)) / c/μ )^(1 / (1 - t)) / µ)
*/
function CVLSharesOutGivenBondsIn(uint256 z, uint256 y, uint256 dy, uint256 t, uint256 c, uint256 mu) returns uint256 {
    yp = require_uint256(y + dy);
    tp = require_uint256(ONE18() - t);
    zp = SharesOutBondsIn(z,y,dy,t,c,mu);
    require YSInvariant(z, zp, y, yp, mu, c, tp);
    return require_uint256(z - zp);
}

function CVLCalculateSpotPrice(uint256 shares, uint256 bonds, uint256 initPrice, uint256 normTime, uint256 timeSt) returns uint256 {
    uint256 tau = mulDivDownAbstractPlus(normTime, timeSt, ONE18());
    uint256 base = mulDivDownAbstractPlus(initPrice, shares, bonds);
    return CVLPow(base, tau);
}