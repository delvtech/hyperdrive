import "./erc20.spec";
import "./MathSummaries.spec";
import "./Sanity.spec";
import "./HyperdriveStorage.spec";

using AaveHyperdrive as HDAave;

use rule sanity;
      
methods {
    function _.mint(address,address,uint256,uint256) external => DISPATCHER(true);
    function _.burn(address,address,uint256,uint256) external => DISPATCHER(true);
    
    function HDAave.MockCalculateFeesOutGivenSharesIn(uint256,uint256,uint256,uint256,uint256) internal returns(AaveHyperdrive.HDFee memory) => NONDET;
    function HDAave.MockCalculateFeesOutGivenBondsIn(uint256,uint256,uint256,uint256) internal returns(AaveHyperdrive.HDFee memory) => NONDET;
    function HDAave.MockCalculateFeesInGivenBondsOut(uint256,uint256,uint256,uint256) internal returns(AaveHyperdrive.HDFee memory) =>NONDET;
}
