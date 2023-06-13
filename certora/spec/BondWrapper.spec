import "./MathSummaries.spec";
import "./Sanity.spec";
import "./erc20.spec";

using ERC20Mintable as baseToken;

use rule sanity;

methods {
    function _.mint(uint256 amount) external => DISPATCHER(true);
    function _.mint(address destination, uint256 amount) external => DISPATCHER(true);

    function _.getAccruedInterest(uint256 time) external => 
                getAccruedInterestCVL(time) expect uint256;
    function _.getAccruedInterest(uint256 time) internal => 
                getAccruedInterestCVL(time) expect uint256;
}

function getAccruedInterestCVL(uint256 time) returns uint256 {
    return interestOverTime[time];
}

ghost mapping(uint256 => uint256) interestOverTime {
    axiom forall uint256 x. forall uint256 y. x > y => interestOverTime[x] >= interestOverTime[y];
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



/* properties:

- BondWrapper.balanceOf(msg.sender) * mintPercent / 10000 >= sum of deposits[msg.sender][assetId]

- 






Questions:








