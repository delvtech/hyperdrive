import "./MathSummaries.spec";
import "./Sanity.spec";
import "./erc20.spec";

using SymbolicHyperdrive as symbHyper;
using DummyERC20A as baseToken;

use rule sanity;

methods { 
    function _.burn(address,address,uint256,uint256) external => DISPATCHER(true);

    function SymbolicHyperdrive.calculateCloseLong(uint256 var1, uint256 var2, uint256 var3) internal returns (SymbolicHyperdrive.GhostVars memory)
        => calculateCloseLongCVL(var1, var2, var3);

}

ghost ghostShareReservesDelta(uint256, uint256, uint256) returns uint256;
ghost ghostBondReservesDelta(uint256, uint256, uint256) returns uint256;
ghost ghostShareProceeds(uint256, uint256, uint256) returns uint256;

function calculateCloseLongCVL(uint256 var1, uint256 var2, uint256 var3) returns SymbolicHyperdrive.GhostVars {
    SymbolicHyperdrive.GhostVars returnValues;
    require returnValues.shareReservesDelta == ghostShareReservesDelta(var1, var2, var3);
    require returnValues.bondReservesDelta == ghostBondReservesDelta(var1, var2, var3);
    require returnValues.shareProceeds == ghostShareProceeds(var1, var2, var3);
    return returnValues;
}


// https://vaas-stg.certora.com/output/3106/41498e14233247a999da53d020d1f672/?anonymousKey=345cf768d96108a7ddd2009626843173cbf1df54
// 12 mins, but it's because of many function combinations so the tool couldn't process all of them in parallel
rule basicFRule(env e, env e2, method f, method g) filtered { f -> !f.isView, g -> !g.isView } {
    calldataarg argsF;
    calldataarg argsG;
    f(e, argsF);
    g(e2, argsG);

    assert false, "Remember, with great power comes great responsibility.";
}


// https://vaas-stg.certora.com/output/3106/9cee794f715243c4afedff5b52dfbce6/?anonymousKey=28d3f6bea3be22ceebe9da9c730257ada11e5470
// 25 mins but it's the run with 3 calls to the heaviest function (close) that took 15 mins
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

