import "./CVLMath.spec";

ghost uint256 CVLFlatFee; /// _flatFee
ghost uint256 CVLGovFee; /// _governanceFee
ghost uint256 CVLCurFee; /// _curveFee

// struct HDFee 
ghost mathint totalCurveFee;
ghost mathint totalFlatFee;
ghost mathint governanceCurveFee;
ghost mathint governanceFlatFee;

function CVLFeesOutGivenAmountsIn(
    uint256 amountIn,
    uint256 normalizedTimeRemaining,
    uint256 spotPrice,
    uint256 sharePrice) returns AaveHyperdrive.HDFee 
{
    havoc totalCurveFee;
    havoc totalFlatFee;
    havoc governanceCurveFee;
    havoc governanceFlatFee;

    require spotPrice <= ONE18();
    require normalizedTimeRemaining <= ONE18();

    require 
        to_mathint(sharePrice) * (totalFlatFee + totalCurveFee) <=
        to_mathint(amountIn) * (CVLFlatFee + CVLCurFee);

        governanceCurveFee = (totalCurveFee * CVLGovFee) / ONE18();
        governanceFlatFee = (totalFlatFee * CVLGovFee) / ONE18();

    AaveHyperdrive.HDFee fee;
    require fee.totalCurveFee == require_uint256(totalCurveFee);
    require fee.totalFlatFee == require_uint256(totalFlatFee);
    require fee.governanceCurveFee == require_uint256(governanceCurveFee);
    require fee.governanceFlatFee == require_uint256(governanceFlatFee);

    return fee;
}

function CVLFeesOutGivenSharesIn(
    uint256 amountIn,
    uint256 amountOut,
    uint256 normalizedTimeRemaining,
    uint256 spotPrice,
    uint256 sharePrice) returns AaveHyperdrive.HDFee 
{
    havoc totalCurveFee;
    havoc totalFlatFee;
    havoc governanceCurveFee;
    havoc governanceFlatFee;

    // curve fee = ((1 / p) - 1) * phi_curve * c * d_z * t
    // p * curve_fee = (1 - p) * phi_curve * c * d_z * t
    // p * curve_fee <= phi_curve * c * d_z
    require spotPrice * totalCurveFee <= (sharePrice * amountIn * CVLCurFee) / ONE18();

    // governanceCurveFee = d_z * (curve_fee / d_y) * c * phi_gov
    // d_y * governanceCurveFee = d*z * curve_fee * c * phi_gov
    require amountOut * governanceCurveFee <= (amountIn * totalCurveFee * spotPrice * CVLGovFee) / (ONE18()*ONE18()); 

    require totalFlatFee <= (sharePrice * amountIn * CVLFlatFee)/(ONE18() * ONE18());
    // calculate the flat portion of the governance fee
    governanceFlatFee = (totalFlatFee * CVLGovFee) / ONE18();

    AaveHyperdrive.HDFee fee;
    require fee.totalCurveFee == require_uint256(totalCurveFee);
    require fee.totalFlatFee == require_uint256(totalFlatFee);
    require fee.governanceCurveFee == require_uint256(governanceCurveFee);
    require fee.governanceFlatFee == require_uint256(governanceFlatFee);

    return fee;
}
