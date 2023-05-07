import "./erc20.spec";
import "./MathSummaries.spec";
import "./Sanity.spec";

using AaveHyperdrive as HDAave;

use rule sanity;

methods {
    function HDAave._pricePerShare() internal returns (uint256);
}
