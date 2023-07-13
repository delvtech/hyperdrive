// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

abstract contract HyperdriveFeeMath {

    struct HDFee {
        uint256 totalCurveFee;
        uint256 totalFlatFee;
        uint256 governanceCurveFee;
        uint256 governanceFlatFee;
    }
    
    function destructHDFee(HDFee memory fee) internal pure returns (uint256,uint256,uint256,uint256) {
        return (fee.totalCurveFee, fee.totalFlatFee, fee.governanceCurveFee, fee.governanceFlatFee);
    }

    function MockCalculateFeesOutGivenSharesIn(
        uint256 _amountIn,
        uint256 _amountOut,
        uint256 _spotPrice,
        uint256 _sharePrice
    ) internal pure returns (HDFee memory) {
        return HDFee(0 *_amountIn,0,0,0);
    }

    function MockCalculateFeesOutGivenBondsIn(
        uint256 _amountIn,
        uint256 _normalizedTimeRemaining,
        uint256 _spotPrice,
        uint256 _sharePrice
    ) internal pure returns (HDFee memory) {
        return HDFee(0 *_amountIn,0,0,0);
    }

    function MockCalculateFeesInGivenBondsOut(
        uint256 _amountOut,
        uint256 _normalizedTimeRemaining,
        uint256 _spotPrice,
        uint256 _sharePrice
    ) internal pure returns (HDFee memory) {
        return HDFee(0 *_amountOut,0,0,0);
    }
}
