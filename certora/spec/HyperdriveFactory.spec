import "./erc20.spec";
import "./MathSummaries.spec";
import "./Sanity.spec";

using HyperdriveMath as HDMath;

use rule sanity;

methods {
    // Hyperdrive
    function _.initialize(uint256, uint256, address, bool) external => DISPATCHER(true);
    // DsrManager
    function _.join(address, uint256) external => DISPATCHER(true);
    function _.daiBalance(address) external => DISPATCHER(true);
    // PotLikeImpl
    function _.vat() external => DISPATCHER(true);
    function _.chi() external => DISPATCHER(true);
    function _.rho() external => DISPATCHER(true);
    function _.drip() external => DISPATCHER(true);
    function _.join(uint256) external => DISPATCHER(true);
    function _.exit(uint256) external => DISPATCHER(true);

    function HDMath.calculateSpotPrice(uint256,uint256,uint256,uint256,uint256) internal returns(uint256) library => NONDET;
    function HDMath.calculateAPRFromReserves(uint256,uint256,uint256,uint256,uint256) internal returns(uint256) => NONDET;
    function HDMath.calculateInitialBondReserves(uint256,uint256,uint256,uint256,uint256,uint256) internal returns(uint256) library => NONDET;
    function HDMath.calculatePresentValue(HyperdriveMath.PresentValueParams memory) internal returns(uint256) library => NONDET;
    function HDMath.calculateShortInterest(uint256,uint256,uint256,uint256) internal returns(uint256) library => NONDET;
    function HDMath.calculateShortProceeds(uint256,uint256,uint256,uint256,uint256) internal returns(uint256) library => NONDET;
}
