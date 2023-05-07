import "./erc20.spec";
import "./MathSummaries.spec";
import "./Sanity.spec";
using HyperdriveMath as HDMath;
using AaveHyperdriveDataProvider as HDDP;

use rule sanity;
 
methods {
    //function HDAave._pricePerShare() internal returns (uint256) => NONDET;

    function HDMath.calculateSpotPrice(uint256,uint256,uint256,uint256,uint256) internal returns(uint256) library => NONDET;
    function HDMath.calculateAPRFromReserves(uint256,uint256,uint256,uint256,uint256) internal returns(uint256) => NONDET;
    function HDMath.calculateInitialBondReserves(uint256,uint256,uint256,uint256,uint256,uint256) internal returns(uint256) library => NONDET;
    function HDMath.calculatePresentValue(HyperdriveMath.PresentValueParams memory) internal returns(uint256) library => NONDET;
    function HDMath.calculateShortInterest(uint256,uint256,uint256,uint256) internal returns(uint256) library => NONDET;
    function HDMath.calculateShortProceeds(uint256,uint256,uint256,uint256,uint256) internal returns(uint256) library => NONDET;
}
