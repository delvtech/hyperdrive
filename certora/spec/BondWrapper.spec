import "./MathSummaries.spec";
import "./Sanity.spec";
import "./erc20.spec";

using ERC20Mintable as baseToken;

use rule sanity;

methods {
    function _.mint(uint256 amount) external => DISPATCHER(true);
    function _.mint(address destination, uint256 amount) external => DISPATCHER(true);
}


rule basicFRule(env e, env e2, method f, method g) filtered { f -> !f.isView, g -> !g.isView } {
    calldataarg argsF;
    calldataarg argsG;
    f(e, argsF);
    g(e2, argsG);

    assert false, "Remember, with great power comes great responsibility.";
}


rule frontRunCheck(env e, env e2, method f) filtered { f -> !f.isView } {
    uint256 maturityTime;
    uint256 amount;
    bool andBurn;
    address destination;
    storage initialStorage = lastStorage; 

    uint256 baseBalanceBefore = baseToken.balanceOf(e, destination);

    close(e, maturityTime, amount, andBurn, destination);

    uint256 baseBalanceAfterSingle = baseToken.balanceOf(e, destination);

    calldataarg args;
    f(e2, args) at initialStorage;

    close(e, maturityTime, amount, andBurn, destination);

    uint256 baseBalanceAfterDouble = baseToken.balanceOf(e, destination);

    assert baseBalanceAfterSingle - baseBalanceBefore 
            == baseBalanceAfterDouble - baseBalanceBefore;
}




