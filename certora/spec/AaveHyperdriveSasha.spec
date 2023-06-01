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


// STATUS - not interesting property
// _checkpoints[_latestCheckpoint()].shortBaseVolume was increased, then _marketState.shortBaseVolume was increased too, and vice versa 
// Only true for openShort and only when a checkpoint was updated before.
// https://vaas-stg.certora.com/output/3106/85862aef974d4ea28c238b735a8c0471/?anonymousKey=776d4d97587056c6ef69f86a6d87371fe5af4c1c
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
// more bonds are opened, more of everything will be paid/received:
// - trader deposit
// - ...
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