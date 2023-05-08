import "./erc20.spec";
import "./MathSummaries.spec";
import "./Sanity.spec";

using AaveHyperdrive as HDAave;

use rule sanity;

methods {
    function _.mint(address,address,uint256,uint256) external => DISPATCHER(true);
    function _.burn(address,address,uint256,uint256) external => DISPATCHER(true);
    function HDAave._pricePerShare() internal returns (uint256);
}
