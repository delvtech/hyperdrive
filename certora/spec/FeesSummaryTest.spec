import "CVLMath.spec";

methods {
    function curveFee() external returns (uint256) envfree;
    function flatFee() external returns (uint256) envfree;
    function governanceFee() external returns (uint256) envfree;

    function _.mulDivDown(uint256 x, uint256 y, uint256 d) internal library => mulDivDownAbstractPlus(x, y, d) expect uint256;
    function _.mulDivUp(uint256 x, uint256 y, uint256 d) internal library => mulDivUpAbstractPlus(x, y, d) expect uint256;
    
    function calculateFeesOutGivenSharesIn(uint256,uint256,uint256,uint256,uint256) 
        external returns(uint256,uint256,uint256,uint256) envfree;

    function calculateFeesOutGivenBondsIn(uint256,uint256,uint256,uint256)
        external returns(uint256,uint256,uint256) envfree;

    function calculateFeesInGivenBondsOut(uint256,uint256,uint256,uint256)
        external returns(uint256,uint256,uint256,uint256) envfree; 
}

ghost uint256 CVLFlatFee {axiom CVLFlatFee <= ONE18();}
ghost uint256 CVLGovFee {axiom CVLGovFee <= ONE18();}
ghost uint256 CVLCurFee {axiom CVLCurFee <= ONE18();}

function setGhostFeesFromStorage() {
    CVLFlatFee = flatFee();
    CVLGovFee = governanceFee();
    CVLCurFee = curveFee();
}

rule FeesOutGivenSharesInSummaryTest(
        uint256 amountIn,
        uint256 amountOut,
        uint256 normalizedTimeRemaining,
        uint256 spotPrice,
        uint256 sharePrice) {
    uint256 totalCurveFee;
    uint256 totalFlatFee;
    uint256 governanceCurveFee;
    uint256 governanceFlatFee;

    setGhostFeesFromStorage();

    totalCurveFee, totalFlatFee, governanceCurveFee, governanceFlatFee = 
        calculateFeesOutGivenSharesIn(amountIn, amountOut, normalizedTimeRemaining, spotPrice, sharePrice);

    assert spotPrice * totalCurveFee <= (sharePrice * amountIn * CVLCurFee) / ONE18();

    // governanceCurveFee = d_z * (curve_fee / d_y) * c * phi_gov
    // d_y * governanceCurveFee = d*z * curve_fee * c * phi_gov
    assert amountOut * governanceCurveFee <= (amountIn * totalCurveFee * spotPrice * CVLGovFee) / (ONE18()*ONE18()); 

    assert to_mathint(totalFlatFee) <= (sharePrice * amountIn * CVLFlatFee)/(ONE18() * ONE18());
    // calculate the flat portion of the governance fee
    assert to_mathint(governanceFlatFee) == (totalFlatFee * CVLGovFee) / ONE18();
}

rule FeesOutGivenBondsInSummaryTest(
        uint256 amountIn,
        uint256 normalizedTimeRemaining,
        uint256 spotPrice,
        uint256 sharePrice) {
    uint256 totalCurveFee;
    uint256 totalFlatFee;
    uint256 totalGovernanceFee;

    setGhostFeesFromStorage();

    totalCurveFee, totalFlatFee, totalGovernanceFee = 
        calculateFeesOutGivenBondsIn(amountIn, normalizedTimeRemaining, spotPrice, sharePrice);

    assert spotPrice <= ONE18();
    assert normalizedTimeRemaining <= ONE18();

    assert 
        to_mathint(sharePrice) * (totalFlatFee + totalCurveFee) <=
        to_mathint(amountIn) * (CVLFlatFee + CVLCurFee);

    assert to_mathint(totalGovernanceFee) == mulDownWad(totalCurveFee,CVLGovFee) + mulDownWad(totalFlatFee,CVLGovFee);
}

rule FeesInGivenBondsOutSummaryTest(
        uint256 amountOut,
        uint256 normalizedTimeRemaining,
        uint256 spotPrice,
        uint256 sharePrice) {
    uint256 totalCurveFee;
    uint256 totalFlatFee;
    uint256 governanceCurveFee;
    uint256 governanceFlatFee;

    setGhostFeesFromStorage();

    totalCurveFee, totalFlatFee, governanceCurveFee, governanceFlatFee = 
        calculateFeesInGivenBondsOut(amountOut, normalizedTimeRemaining, spotPrice, sharePrice);

    assert spotPrice <= ONE18();
    assert normalizedTimeRemaining <= ONE18();

    assert 
        to_mathint(sharePrice) * (totalFlatFee + totalCurveFee) <=
        to_mathint(amountOut) * (CVLFlatFee + CVLCurFee);

    assert to_mathint(governanceCurveFee) == (totalCurveFee * CVLGovFee) / ONE18();
    assert to_mathint(governanceFlatFee) == (totalFlatFee * CVLGovFee) / ONE18();
}