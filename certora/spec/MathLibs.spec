import "./CVLMath.spec";

using MockFixedPointMath as FPMath;
using MockHyperdriveMath as HDMath;

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
}

rule monotonicity(uint256 base1, uint256 base2) {
    uint256 bondAmount;
    uint256 timeRemaining;
    uint256 vol1 = HDMath.calculateBaseVolume(base1, bondAmount, timeRemaining);
    uint256 vol2 = HDMath.calculateBaseVolume(base2, bondAmount, timeRemaining);
    
    assert _monotonicallyIncreasing(base1, base2, vol1, vol2);
}