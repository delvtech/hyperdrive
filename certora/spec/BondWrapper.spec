import "./MathSummaries.spec";
import "./Sanity.spec";
import "./erc20.spec";

using DummyMintableERC20Impl as baseToken;
using AssetIdMock as assetIdMock;
using SymbolicHyperdrive as symbolicHyperdrive;
using BondWrapper as bondWrapper;

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
    function deposits(address, uint256) external returns (uint256) envfree;
}

function getAccruedInterestCVL(uint256 time) returns uint256 {
    return interestOverTime[time];
}

ghost mapping(uint256 => uint256) interestOverTime {
    axiom forall uint256 x. forall uint256 y. x > y => interestOverTime[x] >= interestOverTime[y];
}

ghost mathint balanceSum {
    init_state axiom balanceSum == 0;
}
hook Sload uint256 balance balanceOf[KEY address user] STORAGE {
    require balanceSum >= to_mathint(balance);
}
hook Sstore balanceOf[KEY address user] uint256 balance
    (uint256 old_balance) STORAGE
{
    balanceSum = balanceSum - old_balance + balance;
}


invariant erc20Solvency(env e)
    balanceSum == to_mathint(totalSupply(e));


rule basicFRule(env e, env e2, method f, method g) filtered { f -> !f.isView, g -> !g.isView } {
    calldataarg argsF;
    calldataarg argsG;
    f(e, argsF);
    g(e2, argsG);

    assert false, "Remember, with great power comes great responsibility.";
}


// STATUS - timeout
// other users can't frontrun close()
rule frontRunClose(env e, env e2, method f) 
    filtered { f -> !f.isView && f.selector != sig:sweepAndRedeem(uint256[], uint256).selector
} {
    uint256 maturityTime;
    uint256 amount;
    bool andBurn;
    address destination;
    uint256 minOutput;

    uint256 maturityTimeFr;
    uint256 amountFr;
    bool andBurnFr;
    address destinationFr;
    uint256 minOutputFr;

    require mintPercent() > 10 && mintPercent() < 1000;

    storage initialStorage = lastStorage; 

    uint256 baseBalanceBefore = baseToken.balanceOf(e, destination);

    close(e, maturityTime, amount, andBurn, destination, minOutput);

    uint256 baseBalanceAfterSingle = baseToken.balanceOf(e, destination);

    callHelper(e2, f, maturityTimeFr, amountFr, andBurnFr, destinationFr, minOutputFr, initialStorage);

    close(e, maturityTime, amount, andBurn, destination, minOutput);

    uint256 baseBalanceAfterDouble = baseToken.balanceOf(e, destination);

    assert baseBalanceAfterSingle - baseBalanceBefore 
            == baseBalanceAfterDouble - baseBalanceBefore;
}


// STATUS - in progress (can be violated in many cases)
// - other users can't frontrun mint() 
rule frontRunMint(env e, env e2, method f) 
    filtered { f -> !f.isView && f.selector != sig:sweepAndRedeem(uint256[], uint256).selector
} {
    uint256 maturityTime;
    uint256 amount;
    bool andBurn;
    address destination;
    uint256 minOutput;

    uint256 maturityTimeFr;
    uint256 amountFr;
    bool andBurnFr;
    address destinationFr;
    uint256 minOutputFr;

    uint256 assetIdVar;
    
    require assetIdVar == assetIdMock.encodeAssetId(e, AssetId.AssetIdPrefix.Long, maturityTime);
    require destination != destinationFr;

    storage initialStorage = lastStorage; 

    uint256 balanceBefore = balanceOf(e, destination);
    uint256 hyperBalanceBefore = symbolicHyperdrive.balanceOf(e, assetIdVar, e.msg.sender);

    mint(e, maturityTime, amount, destination);

    uint256 balanceAfterSingle = balanceOf(e, destination);
    uint256 hyperBalanceAfterSingle = symbolicHyperdrive.balanceOf(e, assetIdVar, e.msg.sender);

    callHelper(e2, f, maturityTimeFr, amountFr, andBurnFr, destinationFr, minOutputFr, initialStorage);

    mint(e, maturityTime, amount, destination);

    uint256 balanceAfterDouble = balanceOf(e, destination);
    uint256 hyperBalanceAfterDouble = symbolicHyperdrive.balanceOf(e, assetIdVar, e.msg.sender);

    assert balanceAfterSingle - balanceBefore 
            == balanceAfterDouble - balanceBefore;
    assert e.msg.sender != e2.msg.sender 
                => (hyperBalanceAfterSingle - hyperBalanceBefore 
                    == hyperBalanceAfterDouble - hyperBalanceBefore);
}


// - other users can't frontrun redeem()
rule frontRunRedeem(env e, env e2, method f) 
    filtered { f -> !f.isView && f.selector != sig:sweepAndRedeem(uint256[], uint256).selector
} {
    uint256 maturityTime;
    uint256 amount;
    bool andBurn;
    address destination;
    uint256 minOutput;

    uint256 maturityTimeFr;
    uint256 amountFr;
    bool andBurnFr;
    address destinationFr;
    uint256 minOutputFr;

    require e.msg.sender != e2.msg.sender;

    storage initialStorage = lastStorage; 

    uint256 balanceBefore = balanceOf(e, e.msg.sender);
    uint256 baseBalanceBefore = baseToken.balanceOf(e, e.msg.sender);

    redeem(e, amount);

    uint256 balanceAfterSingle = balanceOf(e, e.msg.sender);
    uint256 baseBalanceAfterSingle = baseToken.balanceOf(e, e.msg.sender);

    callHelper(e2, f, maturityTimeFr, amountFr, andBurnFr, destinationFr, minOutputFr, initialStorage);

    redeem(e, amount);

    uint256 balanceAfterDouble = balanceOf(e, e.msg.sender);
    uint256 baseBalanceAfterDouble = baseToken.balanceOf(e, e.msg.sender);

    assert balanceBefore - balanceAfterSingle
            == balanceBefore - balanceAfterDouble;
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
    uint256 minOutput,
    storage initialStorage
) {
    if (f.selector == sig:mint(uint256, uint256, address).selector) {
        mint(e, maturityTime, amount, destination) at initialStorage;
    } else if (f.selector == sig:close(uint256, uint256, bool, address, uint256).selector) {
        close(e, maturityTime, amount, andBurn, destination, minOutput) at initialStorage;
    } else if (f.selector == sig:sweep(uint256).selector) {
        sweep(e, maturityTime) at initialStorage;
    } else if (f.selector == sig:redeem(uint256).selector) {
        redeem(e, amount) at initialStorage;
    } else {
        calldataarg args;
        f(e, args) at initialStorage;
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


// STATUS - in progress
// monotonicity of close(): more have, more will get
rule closeMonoton(env e, env e2) {
    uint256 maturityTime;
    uint256 amount;
    bool andBurn;
    address destination;
    uint256 minOutput;
    uint256 assetIdVar;
    
    require mintPercent() > 10 && mintPercent() < 1000;
    require assetIdVar == assetIdMock.encodeAssetId(e, AssetId.AssetIdPrefix.Long, maturityTime);
    require e.block.timestamp == e2.block.timestamp;
    require destination != symbolicHyperdrive;

    uint256 amountBeforeSmall = deposits(e.msg.sender, assetIdVar);
    uint256 amountBeforeBig = deposits(e2.msg.sender, assetIdVar);

    uint256 destinationBalanceBefore = baseToken.balanceOf(e, destination);

    storage initialStorage = lastStorage;

    close(e, maturityTime, amountBeforeSmall, andBurn, destination, minOutput);

    uint256 destinationBalanceAfterSmall = baseToken.balanceOf(e, destination);

    close(e2, maturityTime, amountBeforeBig, andBurn, destination, minOutput) at initialStorage;

    uint256 destinationBalanceAfterBig = baseToken.balanceOf(e, destination);

    assert amountBeforeSmall < amountBeforeBig 
            => ((destinationBalanceAfterSmall - destinationBalanceBefore) 
                <= (destinationBalanceAfterBig - destinationBalanceBefore));
}


/// mint() correctly updates msg.sender’s MultiToken balance and
/// sdestination’s BondWrapper balance won’t be decreased.
/// STATUS - verified
rule mintIntegrityUser(env e, env e2) {
    uint256 maturityTime;
    uint256 amount;
    address destination;
    uint256 assetIdVar;
    
    require e.msg.sender != bondWrapper;
    requireInvariant erc20Solvency(e);
    require assetIdVar == assetIdMock.encodeAssetId(e, AssetId.AssetIdPrefix.Long, maturityTime);

    uint256 balanceBefore = balanceOf(e, destination);
    uint256 hyperBalanceBefore = symbolicHyperdrive.balanceOf(e, assetIdVar, e.msg.sender);

    mint(e, maturityTime, amount, destination);

    uint256 balanceAfter = balanceOf(e, destination);
    uint256 hyperBalanceAfter = symbolicHyperdrive.balanceOf(e, assetIdVar, e.msg.sender);

    assert balanceBefore <= balanceAfter;
    assert hyperBalanceBefore - hyperBalanceAfter == to_mathint(amount);
}


// STATUS - verified
rule mintIntegritySystem(env e, env e2) {
    uint256 maturityTime;
    uint256 amount;
    address destination;
    uint256 assetIdVar;
    
    require e.msg.sender != bondWrapper;
    requireInvariant erc20Solvency(e);
    require assetIdVar == assetIdMock.encodeAssetId(e, AssetId.AssetIdPrefix.Long, maturityTime);

    uint256 totalBefore = totalSupply(e);
    uint256 hyperBalanceBefore = symbolicHyperdrive.balanceOf(e, assetIdVar, bondWrapper);

    mint(e, maturityTime, amount, destination);

    uint256 totalAfter = totalSupply(e);
    uint256 hyperBalanceAfter = symbolicHyperdrive.balanceOf(e, assetIdVar, bondWrapper);

    assert totalBefore <= totalAfter;
    assert hyperBalanceAfter - hyperBalanceBefore == to_mathint(amount);
}


/// mint() doesn’t affect the balances of other users on any token involved.
/// STATUS - verified
rule mintIntegrityOthers(env e, env e2) {
    uint256 maturityTime;
    uint256 amount;
    address destination;
    uint256 assetIdVar;
    address randAddr;
    
    require e.msg.sender != bondWrapper;
    requireInvariant erc20Solvency(e);
    require randAddr != destination && randAddr != bondWrapper && randAddr != e.msg.sender;
    require assetIdVar == assetIdMock.encodeAssetId(e, AssetId.AssetIdPrefix.Long, maturityTime);

    uint256 balanceBefore = balanceOf(e, randAddr);
    uint256 hyperBalanceBefore = symbolicHyperdrive.balanceOf(e, assetIdVar, randAddr);

    mint(e, maturityTime, amount, destination);

    uint256 balanceAfter = balanceOf(e, randAddr);
    uint256 hyperBalanceAfter = symbolicHyperdrive.balanceOf(e, assetIdVar, randAddr);

    assert balanceBefore == balanceAfter;
    assert hyperBalanceBefore == hyperBalanceAfter;
}


/// Spliting mint amount into two smaller mint amounts is not profitable.
/// STATUS - verified
rule mintIntegritySmallsVsBig(env e, env e2) {
    uint256 maturityTime;
    uint256 amount; uint256 amount1; uint256 amount2;
    address destination;
    uint256 assetIdVar;
    
    require e.msg.sender != bondWrapper;
    requireInvariant erc20Solvency(e);
    require amount == require_uint256(amount1 + amount2);
    require assetIdVar == assetIdMock.encodeAssetId(e, AssetId.AssetIdPrefix.Long, maturityTime);

    uint256 balanceBefore = balanceOf(e, destination);
    uint256 hyperBalanceBefore = symbolicHyperdrive.balanceOf(e, assetIdVar, e.msg.sender);

    storage initialStorage = lastStorage; 

    mint(e, maturityTime, amount, destination);

    uint256 balanceAfterBig = balanceOf(e, destination);
    uint256 hyperBalanceAfterBig = symbolicHyperdrive.balanceOf(e, assetIdVar, e.msg.sender);

    mint(e, maturityTime, amount1, destination) at initialStorage;
    mint(e, maturityTime, amount2, destination);

    uint256 balanceAfterSmall = balanceOf(e, destination);
    uint256 hyperBalanceAfterSmall = symbolicHyperdrive.balanceOf(e, assetIdVar, e.msg.sender);

    assert balanceAfterBig >= balanceAfterSmall;
    assert hyperBalanceAfterBig == hyperBalanceAfterSmall;
}

/// close() correctly updates msg.sender’s BondWrapper and destination’s ERC20 balances.
/// STATUS - in progress
rule closeIntegrityUser(env e) {
    uint256 maturityTime;
    uint256 amount;
    bool andBurn;
    address destination;
    uint256 minOutput;
    
    require e.msg.sender != bondWrapper && bondWrapper != destination;
    requireInvariant erc20Solvency(e);

    uint256 balanceBefore = balanceOf(e, e.msg.sender);
    uint256 hyperBalanceBefore = baseToken.balanceOf(e, destination);

    close(e, maturityTime, amount, andBurn, destination, minOutput);

    uint256 balanceAfter = balanceOf(e, e.msg.sender);
    uint256 hyperBalanceAfter = baseToken.balanceOf(e, destination);

    assert balanceBefore != balanceAfter => hyperBalanceAfter != hyperBalanceBefore;
    assert hyperBalanceAfter - hyperBalanceBefore >= to_mathint(minOutput);
    assert hyperBalanceAfter - hyperBalanceBefore >= balanceBefore - balanceAfter;
}


// STATUS - in progress
rule closeIntegritySystem(env e) {
    uint256 maturityTime;
    uint256 amount;
    bool andBurn;
    address destination;
    uint256 minOutput;
    
    require e.msg.sender != bondWrapper;
    requireInvariant erc20Solvency(e);

    uint256 totalBefore = totalSupply(e);
    uint256 hyperBalanceBefore = baseToken.balanceOf(e, bondWrapper);

    close(e, maturityTime, amount, andBurn, destination, minOutput);

    uint256 totalAfter = totalSupply(e);
    uint256 hyperBalanceAfter = baseToken.balanceOf(e, bondWrapper);

    assert andBurn => totalBefore >= totalAfter;
    assert hyperBalanceBefore - hyperBalanceAfter >= to_mathint(minOutput);
    assert hyperBalanceAfter - hyperBalanceBefore >= totalBefore - totalAfter;
}


/// close() doesn’t affect the balances of other users on any token involved.
/// STATUS - in progress
rule closeIntegrityOthers(env e) {
    uint256 maturityTime;
    uint256 amount;
    bool andBurn;
    address destination;
    uint256 minOutput;
    address randAddr;
    
    require randAddr != destination && randAddr != bondWrapper && randAddr != e.msg.sender;
    require e.msg.sender != bondWrapper;
    requireInvariant erc20Solvency(e);

    uint256 balanceBefore = balanceOf(e, randAddr);
    uint256 hyperBalanceBefore = baseToken.balanceOf(e, randAddr);

    close(e, maturityTime, amount, andBurn, destination, minOutput);

    uint256 balanceAfter = balanceOf(e, randAddr);
    uint256 hyperBalanceAfter = baseToken.balanceOf(e, randAddr);

    assert balanceBefore == balanceAfter;
    assert hyperBalanceAfter == hyperBalanceBefore;
}
