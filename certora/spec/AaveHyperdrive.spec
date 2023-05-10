import "./erc20.spec";
import "./MathSummaries.spec";
import "./Sanity.spec";
import "./HyperdriveStorage.spec";

using AaveHyperdrive as HDAave;

use rule sanity filtered{f -> f.selector != sig:openShort(uint256,uint256,address,bool).selector
        && f.selector != sig:openLong(uint256,uint256,address,bool).selector}

methods {
    function _.mint(address,address,uint256,uint256) external => DISPATCHER(true);
    function _.burn(address,address,uint256,uint256) external => DISPATCHER(true);
    function HDAave._pricePerShare() internal returns (uint256);
}
