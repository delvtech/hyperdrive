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

    function mintPercent() external returns (uint256) envfree;
    function balanceOf(address) external returns (uint256) envfree;
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


// other users can't frontrun close(), sweep(), redeem() and mint() 
rule frontRunCheck(env e, env e2, method f) 
    filtered { f -> !f.isView && f.selector != sig:sweepAndRedeem(uint256[], uint256).selector
} {
    uint256 maturityTime;
    uint256 amount;
    bool andBurn;
    address destination;

    uint256 maturityTimeFr;
    uint256 amountFr;
    bool andBurnFr;
    address destinationFr;

    storage initialStorage = lastStorage; 

    uint256 baseBalanceBefore = baseToken.balanceOf(e, destination);

    close(e, maturityTime, amount, andBurn, destination);

    uint256 baseBalanceAfterSingle = baseToken.balanceOf(e, destination);

    callHelper(e2, f, maturityTimeFr, amountFr, andBurnFr, destinationFr, initialStorage);

    close(e, maturityTime, amount, andBurn, destination);

    uint256 baseBalanceAfterDouble = baseToken.balanceOf(e, destination);

    assert baseBalanceAfterSingle - baseBalanceBefore 
            == baseBalanceAfterDouble - baseBalanceBefore;
}

function callHelper(
    env e, 
    method f, 
    uint256 maturityTime,
    uint256 amount,
    bool andBurn,
    address destination, 
    storage initialStorage
) {
    if (f.selector == sig:mint(uint256, uint256, address).selector) {
        mint(e, maturityTime, amount, destination) at initialStorage;
    } else if (f.selector == sig:close(uint256, uint256, bool, address).selector) {
        close(e, maturityTime, amount, andBurn, destination) at initialStorage;
    } else if (f.selector == sig:sweep(uint256).selector) {
        sweep(e, maturityTime) at initialStorage;
    } else if (f.selector == sig:redeem(uint256).selector) {
        redeem(e, amount) at initialStorage;
    } else {
        calldataarg args;
        f(e, args);
    }
}


ghost mapping(address => mathint) userDepositSum {
    init_state axiom forall address a. userDepositSum[a] == 0;
}

hook Sload uint256 amount deposits[KEY address user][KEY uint256 assetId]  STORAGE {
    require userDepositSum[user] >= to_mathint(amount);
}

hook Sstore deposits[KEY address user][KEY uint256 assetId] uint256 amount
    (uint256 old_amount) STORAGE
{
    userDepositSum[user] = to_mathint(userDepositSum[user] - old_amount + amount);
}

// STATUS - in progress
// BondWrapper.balanceOf(msg.sender) * mintPercent / 10000 >= sum of deposits[msg.sender][assetId]
invariant test(env e, address user)
    balanceOf(user) * mintPercent() / 10000 >= userDepositSum[user];


/* properties:

- other users can't frontrun close(), sweep(), redeem() and mint() 

- monotonicity of close() and sweep(): more have, more will get

- mint() integrity:
    - user's bond balance is decreased
    - system's bond balance is increased
    - destination gets wrapped bonds but less than amount
    - 2 small mints is not better than 1 big mint

- close() integrity:
    - msg.sender's and destination's bond balances are unchanged
    - system's bond balance is decreased
    - user burns gets wrapped bonds but less than amount
    - destination gets baseToken
    - if fully matured, 2 small closes is not better than 1 big close




Questions:

- close() and secuence sweep(), redeem() for matured bonds seems to be very similar, except the fact the deposits isn't updated. I don't think it's an issue because we have a specific assetId/maturity time slot for each bond, so overflow is almost impossible. But it's inconsistent. What do you think?

- close() and secuence sweep(), redeem(). Calling close() might not burn everything because of the rounding, so we need to call redeem() again. But calling sweep() or redeem() will burn everything because we can set burn amount in redeem(). Is it a problem?

- what value should mintPercent have?

- why do we need two base token transfers in close()? one in closeLong() and another in close() itself?




