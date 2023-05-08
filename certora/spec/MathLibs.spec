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
    function FPMath.exp(int256 x) external returns (int256) envfree;
    function FPMath.ln(int256 x) external returns (int256) envfree;
    function FPMath.updateWeightedAverage(uint256,uint256,uint256,uint256,bool) external returns (uint256) envfree;
    
    function HDMath.calculateBaseVolume(uint256,uint256,uint256) external returns uint256 envfree;
    function HDMath.calculateSpotPrice(uint256,uint256,uint256,uint256,uint256) external returns uint256 envfree;
    function HDMath.calculateAPRFromReserves(uint256,uint256,uint256,uint256,uint256) external returns uint256 envfree;
    function HDMath.calculateInitialBondReserves(uint256,uint256,uint256,uint256,uint256,uint256) external returns uint256 envfree;
    function HDMath.calculatePresentValue(MockHyperdriveMath.PresentValueParams) external returns uint256 envfree;
    function HDMath.calculateShortInterest(uint256,uint256,uint256,uint256) external returns uint256 envfree;
    function HDMath.calculateShortProceeds(uint256,uint256,uint256,uint256,uint256) external returns uint256 envfree;

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

rule monotonicity(uint256 base1, uint256 base2) {
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
