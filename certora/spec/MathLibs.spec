import "./CVLMath.spec";

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

    function _.pow(uint256 x, uint256 y) internal library => CVLPow(x, y) expect uint256;
    
    function HDMath.calculateBaseVolume(uint256,uint256,uint256) external returns uint256 envfree;
    function HDMath.calculateSpotPrice(uint256,uint256,uint256,uint256,uint256) external returns uint256 envfree;
    function HDMath.calculateAPRFromReserves(uint256,uint256,uint256,uint256,uint256) external returns uint256 envfree;
    function HDMath.calculateInitialBondReserves(uint256,uint256,uint256,uint256,uint256,uint256) external returns uint256 envfree;
    function HDMath.calculatePresentValue(MockHyperdriveMath.PresentValueParams) external returns uint256 envfree;
    function HDMath.calculateShortInterest(uint256,uint256,uint256,uint256) external returns uint256 envfree;
    function HDMath.calculateShortProceeds(uint256,uint256,uint256,uint256,uint256) external returns uint256 envfree;
    
    function HDMath.calculateOpenLong(uint256,uint256,uint256,uint256,uint256,uint256) external returns (uint256) envfree;
    function HDMath.calculateCloseLong(uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256) external returns (uint256, uint256, uint256) envfree;
    function HDMath.calculateOpenShort(uint256,uint256,uint256,uint256,uint256,uint256) external returns (uint256) envfree;
    function HDMath.calculateCloseShort(uint256,uint256,uint256,uint256,uint256,uint256,uint256) external returns (uint256, uint256, uint256) envfree;

    function YSMath.calculateBondsInGivenSharesOut(uint256,uint256,uint256,uint256,uint256,uint256) external returns uint256 envfree;
    function YSMath.calculateBondsOutGivenSharesIn(uint256,uint256,uint256,uint256,uint256,uint256) external returns uint256 envfree;
    function YSMath.calculateSharesInGivenBondsOut(uint256,uint256,uint256,uint256,uint256,uint256) external returns uint256 envfree;
    function YSMath.calculateSharesOutGivenBondsIn(uint256,uint256,uint256,uint256,uint256,uint256) external returns uint256 envfree;
}

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

rule mulDownChain(uint256 x, uint256 y, uint256 z) {
    uint256 w = mulDownWad(x, y);
    assert ONE18() * w <= x * y;
    assert ONE18() * ONE18() * mulDownWad(w, z) <= (x * y * z);
}

rule mulDivDownEquivalence(uint256 x, uint256 y, uint256 z) {
    assert FPMath.mulDivDown(x,y,z) == mulDivDownAbstractPlus(x,y,z);
}

rule mulDivUpEquivalence(uint256 x, uint256 y, uint256 z) {
    assert FPMath.mulDivUp(x,y,z) == mulDivUpAbstractPlus(x,y,z);
}

/// Verify the invariant: (c / µ) * (µ * z)^(1 - t) + y^(1 - t) = k
/// t = 0 : (c/mu) *(mu * z) + y = k => c*z + y = k => x + y = k
rule YSInvariantIntegrity() {
    uint256 z1; require z1 !=0;
    uint256 z2; require z2 !=0;
    uint256 y1; 
    uint256 y2; 
    uint256 mu; require mu >= ONE18();
    uint256 c; require c >= mu; // Docs assumption
    uint256 t; require t <= ONE18() && t > 0;

    uint256 mu_z1 = require_uint256(mu * z1);
    uint256 mu_z2 = require_uint256(mu * z2);
    uint256 tp = require_uint256(ONE18() - t);
    
    /// Require invariant equivalent expressions on pairs (z1,y1) and (z2,y2).
    require YSInvariant(z1, z2, y1, y2, mu, c, t);

    mathint k1 = (c / mu) * CVLPow(mu_z1, tp) + CVLPow(y1, tp);
    mathint k2 = (c / mu) * CVLPow(mu_z2, tp) + CVLPow(y2, tp);

    assert k1 == k2;
}

rule monotonicityBaseVolume(uint256 base1, uint256 base2) {
    uint256 bondAmount;
    uint256 timeRemaining;
    uint256 vol1 = HDMath.calculateBaseVolume(base1, bondAmount, timeRemaining);
    uint256 vol2 = HDMath.calculateBaseVolume(base2, bondAmount, timeRemaining);
    
    assert _monotonicallyIncreasing(base1, base2, vol1, vol2);
}

rule YSInvariantTest1(uint256 z, uint256 y, uint256 dz, uint256 t, uint256 c, uint256 mu) {
    uint256 dy = YSMath.calculateBondsInGivenSharesOut(z,y,dz,t,c,mu);

    uint256 yp = require_uint256(y + dy);
    uint256 zp = require_uint256(z - dz);
    uint256 tp = require_uint256(ONE18() - t);
    assert YSInvariant(z, zp, y, yp, mu, c, tp);
}

rule cannotGetFreeBonds(uint256 z, uint256 y, uint256 dy, uint256 t, uint256 c, uint256 mu) {
    
    require mu >= ONE18();
    require c >= mu;
    require y == 0 => z >= ONE18();
    require z == 0 => y >= ONE18();
    require t >= 0 && t <= ONE18();
    uint256 dz = YSMath.calculateSharesInGivenBondsOut(z,y,dy,t,c,mu);

    assert dy !=0 => dz !=0;
}

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
/// @return bondReservesDelta The amount of bonds sold by the curve.

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
