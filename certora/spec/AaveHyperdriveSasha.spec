import "./erc20.spec";
import "./MathSummaries.spec";
import "./Sanity.spec";
import "./HyperdriveStorage.spec";
import "./Fees.spec";

using AaveHyperdrive as HDAave;
using DummyATokenA as aToken;
using Pool as pool;
using MockAssetId as assetId;
using DummyERC20A as baseToken;

use rule sanity;

methods {
    function _.mint(address,address,uint256,uint256) external => DISPATCHER(true);
    function _.burn(address,address,uint256,uint256) external => DISPATCHER(true);

    function aToken.UNDERLYING_ASSET_ADDRESS() external returns (address) envfree;
    function aToken.balanceOf(address) external returns (uint256);
    function aToken.transfer(address,uint256) external returns (bool);
    function pool.liquidityIndex(address,uint256) external returns (uint256) envfree;
    function totalShares() external returns (uint256) envfree;

    function assetId.encodeAssetId(MockAssetId.AssetIdPrefix, uint256) external returns (uint256) envfree;
    function _.encodeAssetId(MockAssetId.AssetIdPrefix, uint256) internal => NONDET;

    function _.recordPrice(uint256) internal => NONDET;
    
    /*
    /// Fee calculations summaries -> NONDET
    function HDAave.MockCalculateFeesOutGivenSharesIn(uint256,uint256,uint256,uint256,uint256) internal returns(AaveHyperdrive.HDFee memory) => NONDET;
    function HDAave.MockCalculateFeesOutGivenBondsIn(uint256,uint256,uint256,uint256) internal returns(AaveHyperdrive.HDFee memory) => NONDET;
    function HDAave.MockCalculateFeesInGivenBondsOut(uint256,uint256,uint256,uint256) internal returns(AaveHyperdrive.HDFee memory) => NONDET;
    */

    /*
    /// Fee calculations summaries -> CVL Summary
    function HDAave.MockCalculateFeesOutGivenSharesIn(uint256 a,uint256 b ,uint256 c ,uint256 d,uint256 e) internal returns(AaveHyperdrive.HDFee memory) =>
        CVLFeesOutGivenSharesIn(a,b,c,d,e);
    function HDAave.MockCalculateFeesOutGivenBondsIn(uint256 a, uint256 b,uint256 c, uint256 d) internal returns(AaveHyperdrive.HDFee memory) =>
        CVLFeesOutGivenAmountsIn(a,b,c,d);
    function HDAave.MockCalculateFeesInGivenBondsOut(uint256 a, uint256 b, uint256 c, uint256 d) internal returns(AaveHyperdrive.HDFee memory) =>
        CVLFeesOutGivenAmountsIn(a,b,c,d);
    */
}

definition LP_ASSET_ID() returns uint256 = 0;
definition WITHDRAWAL_SHARE_ASSET_ID() returns uint256 = (3 << 248);

definition indexA() returns uint256 = require_uint256(RAY()*2);
definition indexB() returns uint256 = require_uint256((RAY()*125)/100);

/// @dev Under-approximation of the pool parameters (based on developers' test)
/// @notice Use only to find violations!
function setHyperdrivePoolParams() {
    require initialSharePrice() == ONE18();
    require timeStretch() == 45071688063194104; /// 5% APR
    require checkpointDuration() == 1;
    require positionDuration() == 31536000;
    require updateGap() == 1000;
    /// Alternative
    require curveFee() == require_uint256(ONE18() / 10);
    require flatFee() == require_uint256(ONE18() / 10);
    require governanceFee() == require_uint256(ONE18() / 2);
    ///
    //require curveFee() <= require_uint256(ONE18() / 10);
    //require flatFee() <= require_uint256(ONE18() / 10);
    //require governanceFee() <= require_uint256(ONE18() / 2);
}

ghost mathint ghostReadyToWithdraw {
    init_state axiom ghostReadyToWithdraw == 0; 
}

ghost mathint sumOfWithdrawalShares {
    init_state axiom sumOfWithdrawalShares == 0; 
}

ghost mathint sumOfLPTokens {
    init_state axiom sumOfLPTokens == 0;
}

hook Sload uint256 index Pool.liquidityIndex[KEY address token][KEY uint256 timestamp] STORAGE {
    /// @WARNING : UNDER-APPROXIMATION!
    /// @notice : to simplify the SMT formulas, we assume to possible values for the index.
    /// so in general, the index as a function of time can have only one of these two values.
    // require index == indexA() || index == indexB();
    //require index >= RAY();
    require index == indexA();
}

hook Sload uint128 value HDAave._withdrawPool.readyToWithdraw STORAGE {
    require ghostReadyToWithdraw == to_mathint(value);
}

hook Sstore HDAave._withdrawPool.readyToWithdraw uint128 value (uint128 old_value) STORAGE {
    ghostReadyToWithdraw = ghostReadyToWithdraw + value - old_value;
}

hook Sload uint256 value HDAave._balanceOf[KEY uint256 tokenID][KEY address account] STORAGE {
    if(tokenID == WITHDRAWAL_SHARE_ASSET_ID()) {
        require sumOfWithdrawalShares >= to_mathint(value); 
    } 
    else if(tokenID == LP_ASSET_ID()) {
        require sumOfLPTokens >= to_mathint(value); 
    }
}

hook Sstore HDAave._balanceOf[KEY uint256 tokenID][KEY address account] uint256 value (uint256 old_value) STORAGE {
    sumOfWithdrawalShares = tokenID == WITHDRAWAL_SHARE_ASSET_ID() ? 
        sumOfWithdrawalShares + value - old_value : sumOfWithdrawalShares;

    sumOfLPTokens = tokenID == LP_ASSET_ID() ?
        sumOfLPTokens + value - old_value : sumOfLPTokens;
}

function getPoolIndex(uint256 timestamp) returns uint256 {
    return pool.liquidityIndex(aToken.UNDERLYING_ASSET_ADDRESS(), timestamp);
}

definition onlyShortMethods(method f) returns bool =
    f.selector == sig:openShort(uint256,uint256,address,bool).selector
        || f.selector == sig:closeShort(uint256,uint256,uint256,address,bool).selector;


/// First assert:
/// https://vaas-stg.certora.com/output/41958/d94981d81dff445ea1b426bcc1f67b5a/?anonymousKey=5e9be1e9f27223a8c656055907909be533fb7c57
/// Second assert:
/// https://vaas-stg.certora.com/output/41958/ee5e46675a6f484aab1c82b32dbcf1ba/?anonymousKey=5b02f66971977f3c6d0606ba567dd5cbbdf29a1a
rule whoChangedTotalShares(method f) filtered { f -> onlyShortMethods(f) } {
    env e;
    calldataarg args;

    setHyperdrivePoolParams();

    uint256 shares1 = totalShares();
    uint256 aTokenBalance1 = aToken.balanceOf(e, currentContract);

    f(e, args);

    uint256 shares2 = totalShares();
    uint256 aTokenBalance2 = aToken.balanceOf(e, currentContract);

    assert shares1 == shares2;
    assert aTokenBalance1 != aTokenBalance2 <=> shares1 != shares2;
}


/// @doc The sum of longs and shorts should not surpass the total amount of bond reserves
/// @notice: should be turned into an invariant
// run without spotPrice calculation and recordPrice call: https://vaas-stg.certora.com/output/3106/89e31f135ecb4d4595379592d2f9c4db/?anonymousKey=1e53b376b0a8527d893d63ce5b1bb2e1e1cd1f63
rule bondsPositionsDontExceedReserves(method f)
filtered { f -> onlyShortMethods(f) } {
    env e;
    calldataarg args;
    AaveHyperdrive.MarketState Mstate1 = marketState();
        f(e, args);
    AaveHyperdrive.MarketState Mstate2 = marketState();

    require Mstate1.longsOutstanding + Mstate1.shortsOutstanding <=
        to_mathint(Mstate1.bondReserves);

    assert Mstate2.longsOutstanding + Mstate2.shortsOutstanding <=
        to_mathint(Mstate2.bondReserves);
}


/*
invariant NoFutureLongTokens(uint256 time, env e)
    time > e.block.timestamp => totalSupplyByToken(assetId.encodeAssetId(MockAssetId.AssetIdPrefix.Long, time)) == 0 
    {
        preserved with (env eP) {
            require e.block.timestamp == eP.block.timestamp;
        }
    }
*/

/// @doc If there are shares in the pool, there must be underlying assets.
// run before removing spot price: https://vaas-stg.certora.com/output/3106/c0b1f3e3a7924af89f6e396ebb342695/?anonymousKey=48024739859961924548574da4229101fa25d310
// https://vaas-stg.certora.com/output/3106/7721e0d6a885469388437cc77ce76652/?anonymousKey=96e97e6efbfec15e9dbedfd69ae1ebc682de4d37
invariant SharesNonZeroAssetsNonZero(env e)
    HDAave.totalShares() !=0 => aToken.balanceOf(e, HDAave) != 0
    filtered { f -> onlyShortMethods(f) }
    {
        preserved with (env eP) {
            setHyperdrivePoolParams();
            require eP.block.timestamp == e.block.timestamp;
            require HDAave.totalShares() >= ONE18();
            require aToken.balanceOf(eP, HDAave) >= ONE18();
        }
    }
    

// https://vaas-stg.certora.com/output/3106/39cdf63c5c43416d8b7c3d36912de263/?anonymousKey=2f171618088d472477af70392c83a12f4ee07eb7
invariant TotalSupplyGEReadyToWithdrawShares()
    to_mathint(totalSupplyByToken(LP_ASSET_ID())) >= ghostReadyToWithdraw
    filtered { f -> onlyShortMethods(f) }
    {
        preserved{
            setHyperdrivePoolParams();
        }
    }

/// @doc The sum of withdrawal shares for all accounts is equal to the shares which are ready to withdraw
/// Violated on removeLiquidity : need to investigate path.
// https://vaas-stg.certora.com/output/3106/5c3bb1afcb04404bae949bbbb23562ba/?anonymousKey=5ee348f908ab779760fa278400836b3f479d76d5
invariant SumOfWithdrawalShares()
    sumOfWithdrawalShares == ghostReadyToWithdraw
    filtered { f -> onlyShortMethods(f) }


/// @doc bond reserves / share reserves >= initial share price
// https://vaas-stg.certora.com/output/3106/b82eb1a6eeda4887888bf56e3fd422b6/?anonymousKey=dbbd1ad62784f132a4055a3882646d7a773fb057
rule maxCurveTradeIntegrity(method f) filtered { f -> onlyShortMethods(f) } {
    env e;
    calldataarg args;
    setHyperdrivePoolParams();
    require (stateBondReserves() * ONE18()) / initialSharePrice() >= to_mathint(stateShareReserves());
        f(e,args);
    assert (stateBondReserves() * ONE18()) / initialSharePrice()  >= to_mathint(stateShareReserves());
}


/// @doc It's impossible to get to a state where both shares and bonds are empty
/// @dev maybe it's possible if all liquidity has been withdrawan?
// https://vaas-stg.certora.com/output/3106/9e6284d50f074d8a981c8e6eed5f3431/?anonymousKey=8216229c38907fb580df5a1855025a4aa009851c
rule cannotCompletelyDepletePool(method f) filtered { f -> onlyShortMethods(f) } {
    env e;
    calldataarg args;
    setHyperdrivePoolParams();
    require require_uint256(stateBondReserves()) >= ONE18() && require_uint256(stateShareReserves()) >= ONE18();
        f(e,args);
    assert !(stateBondReserves() == 0 && stateShareReserves() == 0);
}


// @note I don't see how sharePrice and initialSharePrice are connected
// https://vaas-stg.certora.com/output/3106/2c2fc22366c84b2ba310dc536cf17c80/?anonymousKey=b1c7e0cbdf698c19148c44a6556e71e4ccd5133e
invariant SharePriceCannotDecrease(uint256 checkpointTime)
    checkPointSharePrice(checkpointTime) == 0 || to_mathint(checkPointSharePrice(checkpointTime)) >= to_mathint(initialSharePrice())
    filtered { f -> onlyShortMethods(f) }
    {
        preserved{
            setHyperdrivePoolParams();
            // aTokenBalanceGEToShares
        }
    }


/// @doc There should always be more aTokens (assets) than number of shares
/// otherwise, the share price will decrease (or less than 1).
// https://vaas-stg.certora.com/output/3106/b12b1d0654194afab6c0c5bffd514673/?anonymousKey=b13b6a2d5f3f2b1dd15d5af1050a31031ea57292
//  need to understand AAVE system first: https://vaas-stg.certora.com/output/3106/a7d52cb8ffb244c8844b3b3cfbea4002/?anonymousKey=91ab6620377831f6922efd8a2ec8ea608e598a64
invariant aTokenBalanceGEToShares(env e)
    totalShares() <= aToken.balanceOf(e, currentContract)
    filtered { f -> onlyShortMethods(f) }
    {
        preserved with (env eP) {
            require eP.block.timestamp == e.block.timestamp;
            require eP.msg.sender != currentContract;
            // require balance > RAY
        }
    }

function prestateSetup(env e) {
    require e.msg.sender != currentContract;

}


ghost mathint sumOfAllShares {
    init_state axiom sumOfAllShares == 0;
}

hook Sload uint256 amount _totalSupply[KEY uint256 id]  STORAGE {
    require sumOfAllShares >= to_mathint(amount);
}

hook Sstore _totalSupply[KEY uint256 id] uint256 amount
    (uint256 old_amount) STORAGE
{
    sumOfAllShares = sumOfAllShares + amount - old_amount;
}

/// marketState.shortsOutstanding = sum of open shorts.
rule shortsConsistency(method f, env e)
filtered { f -> onlyShortMethods(f) } {
    setHyperdrivePoolParams();

    AaveHyperdrive.MarketState Mstate1 = marketState();
    require to_mathint(Mstate1.shortsOutstanding) == sumOfAllShares;

    calldataarg args;
    f(e, args);
    
    AaveHyperdrive.MarketState Mstate2 = marketState();

    assert to_mathint(Mstate2.shortsOutstanding) == sumOfAllShares;
}


// STATUS - verified
// trader won't spend more baseTokens/aTokens than maxDeposit.
rule dontSpendMore(env e) {
    setHyperdrivePoolParams();

    uint256 traderBalanceBefore = baseToken.balanceOf(e, e.msg.sender);

    uint256 maxDeposit;
    uint256 _bondAmount;
    address _destination;
    bool _asUnderlying;

    openShort(e, _bondAmount, maxDeposit, _destination, _asUnderlying);

    uint256 traderBalanceAfter = baseToken.balanceOf(e, e.msg.sender);

    assert traderBalanceBefore - traderBalanceAfter <= to_mathint(maxDeposit), "Remember, with great power comes great responsibility.";
}


// STATUS - in progress
// _checkpoints[_latestCheckpoint()].shortBaseVolume was increased, then _marketState.shortBaseVolume was increased too, and vice versa 
// Property is incorrect if we consider all cases.
// For example, in _applyCheckpoint() if a checkpoint wasn't updated then 
// _applyCloseLong or _applyCloseShort can be called, therefore another entity in _checkpoints will be updated
// among with _marketState.shortBaseVolume that is affected at any time.
rule shortBaseVolumeCerrelation(method f, env e) 
filtered { f -> onlyShortMethods(f) } {
    setHyperdrivePoolParams();

    uint256 latestCP = require_uint256(e.block.timestamp -
            (e.block.timestamp % checkpointDuration()));

    AaveHyperdrive.MarketState mState1 = marketState();
    AaveHyperdrive.Checkpoint checkpoint1 = checkPoints(latestCP);
    require checkpoint1.sharePrice > 0;
    
    calldataarg args;
    f(e, args);
    
    AaveHyperdrive.MarketState mState2 = marketState();
    AaveHyperdrive.Checkpoint checkpoint2 = checkPoints(latestCP);

    assert mState1.shortBaseVolume < mState2.shortBaseVolume <=> checkpoint1.shortBaseVolume < checkpoint2.shortBaseVolume;
    assert mState1.shortBaseVolume > mState2.shortBaseVolume <=> checkpoint1.shortBaseVolume > checkpoint2.shortBaseVolume;
    assert mState1.shortBaseVolume == mState2.shortBaseVolume <=> checkpoint1.shortBaseVolume == checkpoint2.shortBaseVolume;
}


// STATUS - in progress
// more bonds are opened, more governance fees will be paid (doesn't work now because all fees are 0)
rule moreBondsMorePayments(env e) {
    setHyperdrivePoolParams();

    uint256 _bondAmount1;
    uint256 _maxDeposit1;
    address _destination1;
    bool _asUnderlying1;

    uint256 _bondAmount2;
    uint256 _maxDeposit2;
    address _destination2;
    bool _asUnderlying2;

    storage initialState = lastStorage;

    uint256 traderBalanceBefore = baseToken.balanceOf(e, e.msg.sender);

    uint256 traderDeposit1 = openShort(e, _bondAmount1, _maxDeposit1, _destination1, _asUnderlying1);

    uint256 traderBalance1 = baseToken.balanceOf(e, e.msg.sender);

    uint256 traderDeposit2 = openShort(e, _bondAmount2, _maxDeposit2, _destination2, _asUnderlying2) at initialState;

    uint256 traderBalance2 = baseToken.balanceOf(e, e.msg.sender);

    assert _bondAmount1 > _bondAmount2 => traderDeposit1 >= traderDeposit2;
    assert _bondAmount1 > _bondAmount2 
                => (traderBalance1 - traderBalanceBefore) >= (traderBalance2 - traderBalanceBefore);
}



function shortFunctionsCallHelper(method f, env e, uint256 maxDeposit) {
    if (f.selector == sig:openShort(uint256, uint256, address, bool).selector) {
        uint256 _bondAmount;
        address _destination;
        bool _asUnderlying;
        openShort(e, _bondAmount, maxDeposit, _destination, _asUnderlying);
    } else if (f.selector == sig:closeShort(uint256, uint256, uint256, address, bool).selector) {

    } else {
        calldataarg args;
        f(e, args);
    }
}