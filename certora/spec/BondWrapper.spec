import "./MathSummaries.spec";
import "./Sanity.spec";
import "./erc20.spec";

using DummyMintableERC20Impl as baseToken;
using AssetIdMock as assetIdMock;
using SymbolicHyperdrive as symbolicHyperdrive;
using BondWrapper as bondWrapper;
using TetherToken as USDT;

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


/// @notice fails in initial state, but it's ok
invariant erc20Solvency(env e)
    balanceSum == to_mathint(totalSupply(e));


/// mint() correctly updates msg.sender’s MultiToken balance and
/// sdestination’s BondWrapper balance won’t be decreased.
/// STATUS - verified
rule mintIntegrityUser(env e, env e2) {
    uint256 maturityTime;
    uint256 amount;
    address destination;
    uint256 assetIdVar;
    
    require e.msg.sender != bondWrapper;
    require destination != symbolicHyperdrive;
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


// STATUS - verified
rule closeIntegrityUser(env e) {
    uint256 maturityTime;
    uint256 amount;
    bool andBurn;
    address destination;
    uint256 minOutput;
    
    require e.msg.sender != bondWrapper && bondWrapper != destination && destination != symbolicHyperdrive;
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


// STATUS - verified
rule closeIntegrityOthers(env e) {
    uint256 maturityTime;
    uint256 amount;
    bool andBurn;
    address destination;
    uint256 minOutput;
    address randAddr;
    
    require randAddr != destination && randAddr != bondWrapper && randAddr != e.msg.sender && randAddr != symbolicHyperdrive;
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


// STATUS - cathces the bug "Unsafe use of transfer()/transferFrom() with IERC20"
rule implementationCorrectness(env e) {
    uint256 maturityTime;
    uint256 amount; uint256 amount2;
    address destination;

    mint(e, maturityTime, amount, destination);
    redeem@withrevert(e, amount2);

    assert lastReverted, "Remember, with great power comes great responsibility.";
}
