import "./CVLMath.spec";
//import "./PresentValue.spec";

using MockFixedPointMath as FPMath;
using MockHyperdriveMath as HDMath;
using MockYieldSpaceMath as YSMath;

methods {
    function FPMath.mulDivDown(uint256, uint256, uint256) external returns (uint256) envfree;
    function FPMath.mulDown(uint256, uint256) external returns (uint256) envfree;
    function FPMath.divDown(uint256, uint256)  external returns (uint256) envfree;
    function FPMath.mulDivUp(uint256, uint256, uint256) external returns (uint256) envfree;
    function FPMath.mulUp(uint256, uint256) external returns (uint256) envfree;
    function FPMath.divUp(uint256, uint256) external returns (uint256) envfree;
    function FPMath.pow(uint256, uint256) external returns (uint256) envfree;
    function FPMath.exp(int256) external returns (int256) envfree;
    function FPMath.ln(int256) external returns (int256) envfree;
    function FPMath.updateWeightedAverage(uint256,uint256,uint256,uint256,bool) external returns (uint256) envfree;

    function _.pow(uint256 x, uint256 y) internal => CVLPow(x, y) expect uint256;
    function _.mulDivDown(uint256 x, uint256 y, uint256 d) internal => mulDivDownAbstractPlus(x, y, d) expect uint256;
    function _.mulDivUp(uint256 x, uint256 y, uint256 d) internal => mulDivUpAbstractPlus(x, y, d) expect uint256;

    function HDMath.calculateBaseVolume(uint256,uint256,uint256) external returns uint256 envfree;
    function HDMath.calculateSpotPrice(uint256,uint256,uint256,uint256) external returns uint256 envfree;
    function HDMath.calculateAPRFromReserves(uint256,uint256,uint256,uint256,uint256) external returns uint256 envfree;
    //function HDMath.calculateInitialBondReserves(uint256,uint256,uint256,uint256,uint256,uint256) external returns uint256 envfree;
    function HDMath.calculatePresentValue(HyperdriveMath.PresentValueParams) external returns (uint256) envfree;
    function HDMath.calculateShortInterest(uint256,uint256,uint256,uint256) external returns uint256 envfree;
    function HDMath.calculateShortProceeds(uint256,uint256,uint256,uint256,uint256) external returns uint256 envfree;

    function HDMath.calculateOpenLong(uint256,uint256,uint256,uint256,uint256,uint256) external returns (uint256) envfree;
    function HDMath.calculateCloseLong(uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256) external returns (uint256, uint256, uint256) envfree;
    function HDMath.calculateOpenShort(uint256,uint256,uint256,uint256,uint256,uint256) external returns (uint256) envfree;
    function HDMath.calculateCloseShort(uint256,uint256,uint256,uint256,uint256,uint256,uint256) external returns (uint256, uint256, uint256) envfree;

    function YSMath.calculateBondsInGivenSharesOut(uint256,uint256,uint256,uint256,uint256,uint256) external returns uint256 envfree;
    function YSMath.calculateBondsOutGivenSharesIn(uint256,uint256,uint256,uint256,uint256,uint256) external returns uint256 envfree;
    function YSMath.calculateSharesInGivenBondsOut(uint256,uint256,uint256,uint256,uint256,uint256) external returns uint256 envfree;
    function YSMath.calculateSharesOutGivenBondsIn(uint256,uint256,uint256,uint256,uint256,uint256) external returns uint256 envfree;
    function YSMath.modifiedYieldSpaceConstant(uint256,uint256,uint256,uint256,uint256) external returns uint256 envfree;
    function YieldSpaceMath.calculateMaxBuy(uint256,uint256,uint256,uint256,uint256) internal returns (uint256, uint256) => NONDET;
}

/// Latest prover report
/// https://prover.certora.com/output/41958/eadef93279954c8aa558ed52305dd795/?anonymousKey=cde9b08b3e4518023d7d0841f3a71b9f5deb309c

function YSInvariant(
    uint256 z1,
    uint256 z2,
    uint256 y1,
    uint256 y2,
    uint256 mu,
    uint256 c,
    uint256 t
    ) returns bool {
    uint256 tp = require_uint256(ONE18() - t); /// t' = 1 - t;
    return c * ONE18() * (CVLPow(z1, tp) - CVLPow(z2, tp)) ==
        to_mathint(CVLPow(mu, t)) * (CVLPow(y2, tp) - CVLPow(y1, tp));
}

function ConvexCurve(
    uint256 z1,
    uint256 z2,
    uint256 y1, 
    uint256 y2, 
    uint256 mu,
    uint256 c, 
    uint256 t
) returns bool {
    uint256 rate1 = mulDownWad(CVLPow(divUpWad(y1, mulDownWad(z1,mu)), t), c);
    //uint256 rate2 = mulDownWad(CVLPow(divUpWad(y2, mulDownWad(z2,mu)), t), c);

    if(z1 == z2) {return (y1 == y2);}
    
    if(y1 > y2) { /// Long
        uint256 margin = divUpWad(require_uint256(y1 - y2), require_uint256(z2 - z1));
        return margin <= rate1;
        //return rate2 <= margin && margin <= rate1;
    }
    else { /// Short
        uint256 margin = divUpWad(require_uint256(y2 - y1), require_uint256(z1 - z2));
        return rate1 <= margin; 
        //return rate1 <= margin && margin <= rate2;
    }
}
/// Verified
rule YSConstant_MonotonicZ(uint256 cDivMu, uint256 mu, uint256 z1, uint256 z2, uint256 t, uint256 y) {
    assert z1 < z2 => 
        YSMath.modifiedYieldSpaceConstant(cDivMu,mu,z1,t,y) <= YSMath.modifiedYieldSpaceConstant(cDivMu,mu,z2,t,y);
}
/// Verified
rule YSConstant_MonotonicY(uint256 cDivMu, uint256 mu, uint256 z, uint256 t, uint256 y1, uint256 y2) {
    assert y1 < y2 => 
        YSMath.modifiedYieldSpaceConstant(cDivMu,mu,z,t,y1) <= YSMath.modifiedYieldSpaceConstant(cDivMu,mu,z,t,y2);
}
/// Verified
rule mulDownChain(uint256 x, uint256 y, uint256 z) {
    uint256 w = mulDownWad(x, y);
    assert ONE18() * w <= x * y;
    assert ONE18() * ONE18() * mulDownWad(w, z) <= (x * y * z);
}
/// Verified
rule mulDivDownEquivalence(uint256 x, uint256 y, uint256 z) {
    assert FPMath.mulDivDown(x,y,z) == mulDivDownAbstractPlus(x,y,z);
}
/// Verified
rule mulDivUpEquivalence(uint256 x, uint256 y, uint256 z) {
    assert FPMath.mulDivUp(x,y,z) == mulDivUpAbstractPlus(x,y,z);
}

/// Violated - need to introduce a new axiom.
rule CVLPow_InverseExponent(uint256 x, uint256 y) {
    require x !=0;
    require y !=0;
    uint256 inv_y = divUpWad(ONE18(), y);
    assert CVLPow(CVLPow(x, y), inv_y) <= x;
}

/// For every number x, and error err,
/// and numbers y1, y2 that border the range [x - %err , x + %err]
/// must be within any error bound err2 >= err.
/// [Verified]
rule errorBoundTest(mathint x, mathint err) {
    require err < to_mathint(ONE18()) && err >= 0;
    mathint err2; require err2 >= err;
    mathint y1 = (x * (ONE18() + err)); 
    mathint y2 = (x * (ONE18() - err));
    assert relativeErrorBound(x * ONE18(), y1, err2) && relativeErrorBound(x * ONE18(), y2, err2);
}
/// Verified
rule calculateSpotPriceMonotonicOnShares() {
    uint256 shareReserves1;
    uint256 bondReserves1;
    uint256 _initialSharePrice1;
    uint256 _timeRemaining1;
    uint256 _timeStretch1;

    uint256 shareReserves2;

    uint256 spotPrice1 = HDMath.calculateSpotPrice(shareReserves1,bondReserves1,_initialSharePrice1,_timeStretch1);
    uint256 spotPrice2 = HDMath.calculateSpotPrice(shareReserves2,bondReserves1,_initialSharePrice1,_timeStretch1);
    assert shareReserves1 <= shareReserves2 => spotPrice1 <= spotPrice2;
}
/// Verified
rule calculateSpotPriceMonotonicOnBonds() {
    uint256 shareReserves1;
    uint256 bondReserves1;
    uint256 _initialSharePrice1;
    uint256 _timeRemaining1;
    uint256 _timeStretch1;

    uint256 bondReserves2;

    uint256 spotPrice1 = HDMath.calculateSpotPrice(shareReserves1,bondReserves1,_initialSharePrice1,_timeStretch1);
    uint256 spotPrice2 = HDMath.calculateSpotPrice(shareReserves1,bondReserves2,_initialSharePrice1,_timeStretch1);
    assert bondReserves1 <= bondReserves2 => spotPrice1 >= spotPrice2;
}

/// Timeout
rule calculateCloseLongMonotonicOnBondReserves(env e) {
    uint256 _shareReserves;
    uint256 _bondReserves1;
    uint256 _amountIn;
    uint256 _normalizedTimeRemaining;
    uint256 _timeStretch;
    uint256 _openSharePrice;
    uint256 _closeSharePrice;
    uint256 _sharePrice;
    uint256 _initialSharePrice;
    uint256 _bondReserves2;

    uint256 shareReservesDelta1;
    uint256 shareReservesDelta2;
    uint256 bondReservesDelta1;
    uint256 bondReservesDelta2;
    uint256 shareProceeds1;
    uint256 shareProceeds2;

    shareReservesDelta1, bondReservesDelta1, shareProceeds1 = HDMath.calculateCloseLong(
        _shareReserves, _bondReserves1, _amountIn, _normalizedTimeRemaining, _timeStretch, _openSharePrice, _closeSharePrice, _sharePrice, _initialSharePrice
    );
    shareReservesDelta2, bondReservesDelta2, shareProceeds2 = HDMath.calculateCloseLong(
        _shareReserves, _bondReserves2, _amountIn, _normalizedTimeRemaining, _timeStretch, _openSharePrice, _closeSharePrice, _sharePrice, _initialSharePrice
    );

    assert _bondReserves1 >= _bondReserves2 => shareProceeds1 >= shareProceeds2;
}

rule calculateSharesOutGivenBondsInMonotonic(uint256 bondReserves1, uint256 bondReserves2) { 
    uint256 shareReserves;
    uint256 timeStretch; 
    require timeStretch >=0 && timeStretch<= ONE18();
    uint256 bondsDelta;
    uint256 sharePrice;
    uint256 initialSharePrice;
    
    uint256 sharesOut1 = YSMath.calculateSharesOutGivenBondsIn(shareReserves, bondReserves1, bondsDelta, timeStretch, sharePrice, initialSharePrice);
    uint256 sharesOut2 = YSMath.calculateSharesOutGivenBondsIn(shareReserves, bondReserves2, bondsDelta, timeStretch, sharePrice, initialSharePrice);

    assert bondReserves1 >= bondReserves2 => sharesOut1 >= sharesOut2;
}


/// Verify the invariant: (c / µ) * (µ * z)^(1 - t) + y^(1 - t) = k
/// t = 0 : (c/mu) *(mu * z) + y = k => c*z + y = k => x + y = k
/// [Verified]
rule YSInvariantIntegrity() {
    uint256 z1; require z1 !=0;
    uint256 z2; require z2 !=0;
    uint256 y1;
    uint256 y2;
    uint256 mu; require mu == ONE18();
    uint256 c; require c >= mu; // Docs assumption
    uint256 t; require t <= ONE18() && t > 0;

    uint256 mu_z1 = mulDownWad(mu, z1);
    uint256 mu_z2 = mulDownWad(mu, z2);
    uint256 tp = require_uint256(ONE18() - t);
    uint256 c_Mu = divDownWad(c, mu);

    /// Require invariant equivalent expressions on pairs (z1,y1) and (z2,y2).
    require YSInvariant(z1, z2, y1, y2, mu, c, t);

    mathint k1 = c_Mu * CVLPow(mu_z1, tp) + CVLPow(y1, tp);
    mathint k2 = c_Mu * CVLPow(mu_z2, tp) + CVLPow(y2, tp);

    assert relativeErrorBound(k1, k2, 10);
}
/// Verified
rule monotonicityBaseVolume(uint256 base1, uint256 base2) {
    uint256 bondAmount;
    uint256 timeRemaining;
    uint256 vol1 = HDMath.calculateBaseVolume(base1, bondAmount, timeRemaining);
    uint256 vol2 = HDMath.calculateBaseVolume(base2, bondAmount, timeRemaining);

    assert _monotonicallyIncreasing(base1, base2, vol1, vol2);
}
/// Violated
rule YSInvariantTest1(uint256 z, uint256 y, uint256 dz, uint256 t, uint256 c, uint256 mu) {
    uint256 dy = YSMath.calculateBondsInGivenSharesOut(z,y,dz,t,c,mu);
    uint256 yp = require_uint256(y + dy);
    uint256 zp = require_uint256(z - dz);
    uint256 tp = require_uint256(ONE18() - t);
    assert YSInvariant(z, zp, y, yp, mu, c, tp);
}
/// Violated
rule ConvexCurveTest(uint256 z, uint256 y, uint256 dz, uint256 t, uint256 c, uint256 mu) {
    uint256 dy = YSMath.calculateBondsInGivenSharesOut(z,y,dz,t,c,mu);
    require t == 45071688063194104;
    require c >= ONE18();
    require mu == ONE18();
    require divUpWad(y, mulDownWad(z,mu)) >= ONE18();
    require dz > 0;
    uint256 yp = assert_uint256(y + dy);
    uint256 zp = assert_uint256(z - dz);
    uint256 tp = assert_uint256(ONE18() - t);
    assert ConvexCurve(z, zp, y, yp, mu, c, tp);
}
/// Violated
rule cannotGetFreeBonds(uint256 z, uint256 y, uint256 dy, uint256 t, uint256 c, uint256 mu) {

    require mu >= ONE18();
    require c >= mu;
    require y == 0 => z >= ONE18();
    require z == 0 => y >= ONE18();
    require t >= 0 && t <= ONE18();
    uint256 dz = YSMath.calculateSharesInGivenBondsOut(z,y,dy,t,c,mu);

    assert dy !=0 => dz !=0;
}
/// Violated
rule cannotGetFreeShares(uint256 z, uint256 y, uint256 dz, uint256 t, uint256 c, uint256 mu) {
    require mu >= ONE18();
    require c >= mu;
    require y == 0 => z >= ONE18();
    require z == 0 => y >= ONE18();
    require t >= 0 && t <= ONE18();
    uint256 dy = YSMath.calculateBondsInGivenSharesOut(z,y,dz,t,c,mu);

    assert dz !=0 => dy !=0;
}

// ======================================
//        Hyperdrive Math rules
//=======================================
/// Verified
rule calculateOpenLong_correctBound(
    uint256 shareReserves,
    uint256 bondReserves,
    uint256 shareAmount,
    uint256 timeStretch,
    uint256 sharePrice,
    uint256 initialSharePrice) {

    require initialSharePrice == ONE18();
    require timeStretch == 45071688063194104;

    uint256 bondReservesDelta = HDMath.calculateOpenLong(
        shareReserves,bondReserves,shareAmount,timeStretch,sharePrice,initialSharePrice);

    assert bondReservesDelta <= bondReserves,
        "The bond reserve delta cannot exceed the bond reserves";
}
/// Timeout
rule calculateOpenLong_ShareMonotonic(
    uint256 shareReserves,
    uint256 bondReserves,
    uint256 shareAmount1,
    uint256 shareAmount2,
    uint256 timeStretch,
    uint256 sharePrice,
    uint256 initialSharePrice) {
        
    require initialSharePrice == ONE18();
    require timeStretch == 45071688063194104;
    require shareAmount1 < shareAmount2;

    uint256 bondReservesDelta1 = HDMath.calculateOpenLong(
        shareReserves,bondReserves,shareAmount1,timeStretch,sharePrice,initialSharePrice);

    uint256 bondReservesDelta2 = HDMath.calculateOpenLong(
        shareReserves,bondReserves,shareAmount2,timeStretch,sharePrice,initialSharePrice);

    assert bondReservesDelta1 <= bondReservesDelta2,
        "The bond reserves delta should increase with the amount of shares";
}
/// Violated
rule calculateOpenLong_BondsMonotonic(
    uint256 shareReserves,
    uint256 bondReserves1,
    uint256 bondReserves2,
    uint256 shareAmount,
    uint256 timeStretch,
    uint256 sharePrice,
    uint256 initialSharePrice) {
        
    require initialSharePrice == ONE18();
    require timeStretch == 45071688063194104;
    require bondReserves1 < bondReserves2;
    require sharePrice >= initialSharePrice;

    uint256 bondReservesDelta1 = HDMath.calculateOpenLong(
        shareReserves,bondReserves1,shareAmount,timeStretch,sharePrice,initialSharePrice);

    uint256 bondReservesDelta2 = HDMath.calculateOpenLong(
        shareReserves,bondReserves2,shareAmount,timeStretch,sharePrice,initialSharePrice);

    assert bondReservesDelta1 <= bondReservesDelta2,
        "The bond reserves delta should increase with increasing bonds reserves";
}

/// Opening and closing a long immediately (with no time elpased between or any other trade),
/// must obey the following conditions:
/// 1. The difference in shares must be equal to the share proceeds
/// 2. The amount of bonds returned to the pool is the same number the trader closed with.
/// Violated (third assert)
rule openAndCloseLongOnCurve(
    uint256 shareReserves,
    uint256 bondReserves,
    uint256 shareAmount,
    uint256 sharePrice) {
    uint256 initialSharePrice = ONE18();
    uint256 timeStretch = 45071688063194104;
    require sharePrice >= initialSharePrice;
    require shareAmount >= 10^9;
    
    uint256 bondDelta1 = HDMath.calculateOpenLong(
        shareReserves, bondReserves, shareAmount, timeStretch, sharePrice, initialSharePrice);

    /// Immediate close - > timeRemaining = 1.
    uint256 timeRemaining = ONE18();
    /// New shares in the pool after opening a long (increase by shareAmount)
    uint256 newShares = require_uint256(shareReserves + shareAmount);
    /// New bonds in the pool after opening a long (decrease by delta)
    uint256 newBonds = require_uint256(bondReserves - bondDelta1);

    uint256 shareReservesDelta;
    uint256 bondReservesDelta;
    uint256 shareProceeds;
    uint256 onePercent = require_uint256(ONE18()/100);
    shareReservesDelta, bondReservesDelta, shareProceeds = HDMath.calculateCloseLong(
        newShares, newBonds, bondDelta1, timeRemaining,
        timeStretch, sharePrice, sharePrice, sharePrice, initialSharePrice);

    assert shareReservesDelta == shareProceeds, "The proceeds must be equal to the amount drained from the pool";
    assert bondReservesDelta == bondDelta1, "Trader must pay the exact amount of bonds";
    assert shareProceeds >= shareAmount  => relativeErrorBound(shareAmount, shareProceeds, onePercent),
        "Trader cannot gain from an immediate round-trip";
}

/// Same as openAndCloseLongOnCurve, but only with YS Math.
/// Violated
rule BondsOutSharesInAndBack(
    uint256 shareReserves,
    uint256 bondReserves,
    uint256 shareAmount,
    uint256 sharePrice) {

    uint256 initialSharePrice = ONE18();
    uint256 timeStretch = 1;//45071688063194104;
    uint256 tp = require_uint256(ONE18() - timeStretch);
    require sharePrice >= initialSharePrice;
    require bondReserves >= shareReserves; // r >= 1
    /// Typical number
    require shareReserves == ONE18();

    uint256 bondsDelta = YSMath.calculateBondsOutGivenSharesIn(shareReserves, bondReserves, shareAmount, tp, sharePrice, initialSharePrice);
    uint256 newShares = require_uint256(shareReserves + shareAmount);
    uint256 newBonds = require_uint256(bondReserves - bondsDelta);
    uint256 sharesOut = YSMath.calculateSharesOutGivenBondsIn(newShares, newBonds, bondsDelta, tp, sharePrice, initialSharePrice);

    assert abs(shareAmount - sharesOut) <= 100, "Trader cannot gain from an immediate round-trip";
}
/// Violated
rule moreBondsMorePaymentsForOpenLong(env e) {
    uint256 _bondAmount1;
    uint256 _shareAmount1; // depends on the bond price (need to prove monotonicity of _calculateOpenShort())
    uint256 _openSharePrice; // is determined by the latest checkpoint. can assume it's the same.
    uint256 _closeSharePrice;  // is determined by the latest checkpoint. can assume it's the same.
    uint256 _sharePrice;   // is determined by the latest checkpoint. can assume it's the same.

    uint256 _bondAmount2;
    uint256 _shareAmount2;

    uint256 traderDeposit1 = HDMath.calculateShortProceeds(_bondAmount1, _shareAmount1, _openSharePrice, _closeSharePrice, _sharePrice);

    uint256 traderDeposit2 = HDMath.calculateShortProceeds(_bondAmount2, _shareAmount2, _openSharePrice, _closeSharePrice, _sharePrice);

    assert _bondAmount1 > _bondAmount2 => traderDeposit1 >= traderDeposit2;
}
/// Verified
rule calculateBaseVolumeCheck(uint256 base, uint256 bonds, uint256 time) {
    require time <= ONE18() && time != 0;
    uint256 volume = HDMath.calculateBaseVolume(base, bonds, time);
    
    assert time == ONE18() => volume == base;

    assert 
        to_mathint(base) <= max(to_mathint(volume), to_mathint(bonds)) &&
        to_mathint(base) >= min(to_mathint(volume), to_mathint(bonds));
}
/// Violated
rule updateWeightedAverageCheck(uint256 avg, uint256 totW, uint256 del, uint256 delW) {
    bool isAdd;
    uint256 avg_new = FPMath.updateWeightedAverage(avg,totW,del,delW,isAdd);
    mathint DeltAvg = avg_new - avg;
    if(isAdd) {
        assert weightedAverage(del-avg,delW,totW,DeltAvg);
    }
    else {
        assert weightedAverage(del-avg,0-delW,totW,DeltAvg);
    }
    /*
    if(delW == totW && !isAdd) {assert DeltAvg == 0;}
    else {
        assert 
        (abs(delW) < abs(totW) => abs(DeltAvg) <= abs(del-avg)/2 ) &&
        (abs(delW) >= abs(totW) => abs(DeltAvg) >= abs(del-avg)/2);
    }*/
}

/// @doc Rules to check the integrity of curve-trading:
/// The trading should always preserve the positivity of the interest r, where
/// r + 1 = y/(z*mu)
/// - y : bonds reserves
/// - z : shares reserves
/// - mu : initial share price
/// There are 4 different rules that correspond to 4 different trading functions inside YSMath.

/// Violated (negative interest should be excluded on the higher-level functions)
rule tradingOnCurvePreservesPositiveInterest1(uint256 z, uint256 y, uint256 dz, uint256 c) {
    require z >= ONE18();
    uint256 timeStretch; require timeStretch < ONE18() && timeStretch > 0;
    uint256 mu = ONE18(); require c >= mu;
    uint256 dy = YSMath.calculateBondsOutGivenSharesIn(z, y, dz, timeStretch, c, mu);
    uint256 y_new = assert_uint256(y - dy);
    uint256 z_new = assert_uint256(z + dz);

    uint256 R1 = mulDivDownAbstractPlus(z, mu, y);
    uint256 R2 = mulDivDownAbstractPlus(z_new, mu, y_new);

    assert R1 <= ONE18() => R2 <= ONE18();   
}

/// Verified
rule tradingOnCurvePreservesPositiveInterest2(uint256 z, uint256 y, uint256 dz, uint256 c) {
    uint256 timeStretch; require timeStretch < ONE18() && timeStretch > 0;
    uint256 mu = ONE18();
    uint256 dy = YSMath.calculateBondsInGivenSharesOut(z, y, dz, timeStretch, c, mu);
    uint256 y_new = assert_uint256(y + dy);
    uint256 z_new = assert_uint256(z - dz);

    uint256 R1 = mulDivDownAbstractPlus(z, mu, y);
    uint256 R2 = mulDivDownAbstractPlus(z_new, mu, y_new);

    assert R1 <= ONE18() => R2 <= ONE18();   
}

/// Violated (negative interest should be excluded on the higher-level functions)
rule tradingOnCurvePreservesPositiveInterest3(uint256 z, uint256 y, uint256 dy, uint256 c) {
    require z >= ONE18();
    uint256 timeStretch; require timeStretch < ONE18() && timeStretch > 0;
    uint256 mu = ONE18(); require c >= mu;
    uint256 dz = YSMath.calculateSharesInGivenBondsOut(z, y, dy, timeStretch, c, mu);
    uint256 y_new = assert_uint256(y - dy);
    uint256 z_new = assert_uint256(z + dz);

    uint256 R1 = mulDivDownAbstractPlus(z, mu, y);
    uint256 R2 = mulDivDownAbstractPlus(z_new, mu, y_new);

    assert R1 <= ONE18() => R2 <= ONE18();   
}

/// Verified
rule tradingOnCurvePreservesPositiveInterest4(uint256 z, uint256 y, uint256 dy, uint256 c) {
    uint256 timeStretch; require timeStretch < ONE18() && timeStretch > 0;
    uint256 mu = ONE18();
    uint256 dz = YSMath.calculateSharesOutGivenBondsIn(z, y, dy, timeStretch, c, mu);
    uint256 y_new = assert_uint256(y + dy);
    uint256 z_new = assert_uint256(z - dz);

    uint256 R1 = mulDivDownAbstractPlus(z, mu, y);
    uint256 R2 = mulDivDownAbstractPlus(z_new, mu, y_new);

    assert R1 <= ONE18() => R2 <= ONE18();
}
/// Violated
rule shortProceedsIntegrity(uint256 bondAmount) {
    uint256 openSharePrice;
    uint256 sharePrice;

    uint256 shareReserves; // share reserves
    uint256 bondReserves; // bond reserves
    uint256 timeStretch; require timeStretch < ONE18() && timeStretch > 0;
    
    require sharePrice >= ONE18();
    require openSharePrice >= ONE18();
    require shareReserves >= ONE18();
    require bondReserves >= ONE18();
    require bondAmount >= 1000000;

    bool sharePriceIncreases = sharePrice >= openSharePrice;

    uint256 shareReservesDelta = HDMath.calculateOpenShort(shareReserves,bondReserves,bondAmount,timeStretch,sharePrice,ONE18());
    require mulDownWad(shareReservesDelta,sharePrice) <= bondAmount;

    uint256 traderDeposit = 
        HDMath.calculateShortProceeds(bondAmount,shareReservesDelta,openSharePrice,sharePrice,sharePrice);

    assert bondAmount !=0 => traderDeposit !=0;
}
/// Violated (old version)
rule presentValueIncludesPoolShares() {
    HyperdriveMath.PresentValueParams params;
    uint256 z = params.shareReserves;
    require params.longsOutstanding == 0;
    require params.shortsOutstanding == 0;
    require params.longAverageTimeRemaining == 0;
    require params.shortAverageTimeRemaining == 0;
    uint256 PV = HDMath.calculatePresentValue(params);
    assert to_mathint(PV) >= z - params.minimumShareReserves; /// New version
}
