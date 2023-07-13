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
using MockHyperdriveMath as HDMath;
using MockYieldSpaceMath as YSMath;

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

    function HDMath.calculateShortProceeds(uint256,uint256,uint256,uint256,uint256) external returns uint256 envfree;
    
    function YSMath.calculateSharesOutGivenBondsIn(uint256,uint256,uint256,uint256,uint256,uint256) external returns uint256 envfree;

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

definition onlyShortMethods(method f) returns bool =
    f.selector == sig:openShort(uint256,uint256,address,bool).selector
        || f.selector == sig:closeShort(uint256,uint256,uint256,address,bool).selector;

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
// failing (need to prove _shareAmount): https://vaas-stg.certora.com/output/3106/c8cf384bc8e64aefaa0f3c81450155e2/?anonymousKey=723ce2ad4f397856acb6a0aedc04fdd7c40cc27a
// more bonds are opened, more trader will deposit
// calling two openShort()'s with lastStorage causes timeouts.
// proving properties of math functions responsible calculations 
rule moreBondsMorePayments(env e) {
    uint256 _bondAmount1;
    uint256 _shareAmount1; // depends on the bond price (need to prove monotonicity of _calculateOpenShort())
    uint256 _openSharePrice; // is determined by the latest checkpoint. can assume it's the same.
    uint256 _closeSharePrice;  // is determined by the latest checkpoint. can assume it's the same.
    uint256 _sharePrice;   // is determined by the latest checkpoint. can assume it's the same.

    uint256 _bondAmount2;
    uint256 _shareAmount2;

    uint256 traderDeposit1 = HDMath.calculateShortProceeds(_bondAmount1, _shareAmount1, _openSharePrice, _closeSharePrice, _sharePrice);

    uint256 traderDeposit2 = HDMath.calculateShortProceeds(_bondAmount2, _shareAmount2, _openSharePrice, _closeSharePrice, _sharePrice);

    assert _bondAmount1 > _bondAmount2 => traderDeposit1 >= traderDeposit2;
}


// STATUS - in progress (failing with summarization: https://vaas-stg.certora.com/output/3106/05f08894193e458aaf2d9892386cf2b8/?anonymousKey=aec08a2cb376b73a55e7e0756ee79a24b2852414)
// proving it for _shareAmount in the rule above
rule calculateSharesOutGivenBondsInMonoton(env e) {
    uint256 _shareReserves;
    uint256 _bondReserves;
    uint256 _amountIn1;
    uint256 _amountIn2;
    uint256 _timeStretch;
    uint256 timeStretch = require_uint256(ONE18() - _timeStretch);
    uint256 _sharePrice;
    uint256 _initialSharePrice;

    uint256 output1 = YSMath.calculateSharesOutGivenBondsIn(_shareReserves, _bondReserves, _amountIn1, timeStretch, _sharePrice, _initialSharePrice);

    uint256 output2 = YSMath.calculateSharesOutGivenBondsIn(_shareReserves, _bondReserves, _amountIn2, timeStretch, _sharePrice, _initialSharePrice);

    assert _amountIn1 > _amountIn2 => output1 >= output2;
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


// _marketState.shortBaseVolume should be greater or equal to traderDeposit ?
// _marketState.shortBaseVolume >= _checkpoints[any].shortBaseVolume
// 


// Timeout
rule checkpointFrontRunsCloseShort(uint256 checkpointTime) {
    env e;
    calldataarg args;
    
    setHyperdrivePoolParams();
    require require_uint256(stateShareReserves()) == ONE18();
    storage initState = lastStorage;

    closeShort(e, args);

    checkpoint(e, checkpointTime) at initState;
    closeShort@withrevert(e, args);

    assert !lastReverted;
}


// @doc There should always be more aTokens (assets) than number of shares
// otherwise, the share price will decrease (or less than 1).
invariant aTokenBalanceGEToShares(env e)
    totalShares() <= aToken.balanceOf(e, currentContract)
    filtered { f -> onlyShortMethods(f) }
    {
        preserved with (env eP) {
            require eP.block.timestamp == e.block.timestamp;
        }
    }


rule SharePriceCannotDecreaseInTime(method f) filtered { f -> onlyShortMethods(f) } {
    env e;
    calldataarg args;
    uint256 sharePriceBefore = sharePrice(e);
        f(e, args);
    uint256 sharePriceAfter = sharePrice(e);

    assert sharePriceAfter >= sharePriceBefore;
}

