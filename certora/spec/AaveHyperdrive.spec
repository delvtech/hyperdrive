import "./erc20.spec";
import "./MathSummaries.spec";
import "./Sanity.spec";
import "./HyperdriveStorage.spec";
import "./LiquidityDefinitions.spec";
//import "./Fees.spec";

using AaveHyperdrive as HDAave;
using DummyATokenA as aToken;
using Pool as pool;
using MockAssetId as assetId;

use rule sanity;

methods {
    function _.mint(address,address,uint256,uint256) external => DISPATCHER(true);
    function _.burn(address,address,uint256,uint256) external => DISPATCHER(true);

    function aToken.UNDERLYING_ASSET_ADDRESS() external returns (address) envfree;
    function aToken.balanceOf(address) external returns (uint256);
    function aToken.transfer(address,uint256) external returns (bool);
    function pool.liquidityIndex(address,uint256) external returns (uint256) envfree;
    function totalShares() external returns (uint256) envfree;
    function getPresentValue(uint256) external returns (uint256);

    function MockAssetId.encodeAssetId(MockAssetId.AssetIdPrefix, uint256) external returns (uint256) envfree;
    function _.recordPrice(uint256 price) internal => NONDET;

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

definition indexA() returns uint256 = require_uint256(RAY()*2);
definition indexB() returns uint256 = require_uint256((RAY()*125)/100);

/// @dev Under-approximation of the pool parameters (based on developers' test)
/// @notice Use only to find violations!
function setHyperdrivePoolParams() {
    require initialSharePrice() == ONE18();
    require timeStretch() == 45071688063194104; /// 5% APR
    require checkpointDuration() == 86400;
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


hook Sload uint256 index Pool.liquidityIndex[KEY address token][KEY uint256 timestamp] STORAGE {
    /// @WARNING : UNDER-APPROXIMATION!
    /// @notice : to simplify the SMT formulas, we assume a specific value for the index.
    /// so in general, the index as a function of time is actually a constant.
    require index == indexA();// || index == indexB();
    //require index >= RAY();
}

function getPoolIndex(uint256 timestamp) returns uint256 {
    return pool.liquidityIndex(aToken.UNDERLYING_ASSET_ADDRESS(), timestamp);
}

/// @notice Simulates the output of the `_deposit()` function
/// @param totalSharesBefore - totalShares before deposit function
/// @param assetsBefore - assets of contract before deposit function.
/// @param baseAmount - The amount of token to transfer
/// @param asUnderlying - underlying tokens (true) or yield source tokens (false)
/// @return output[0] = sharesMinted
/// @return output[1] = sharePrice
function depositOutput(env e, uint256 totalSharesBefore, uint256 assetsBefore, uint256 baseAmount, bool asUnderlying) returns uint256[2] {
    uint256[2] output;
    uint256 totalSharesAfter = totalShares();
    uint256 assetsAfter = aToken.balanceOf(e, HDAave);
    uint256 index = getPoolIndex(e.block.timestamp);

    if(totalSharesBefore == 0) {
        require baseAmount == output[0];
        require ONE18() == output[1];
    }
    else {
        if(asUnderlying) {
            require baseAmount > 0 => assetsBefore < assetsAfter;
        }
        else {
            require to_mathint(assetsAfter) >= assetsBefore + baseAmount;
            require to_mathint(assetsAfter) <= assetsBefore + baseAmount + index/RAY();
        }
        require mulDivDownAbstractPlus(totalSharesBefore, baseAmount, assetsBefore) == output[0];
        require mulDivDownAbstractPlus(baseAmount, ONE18(), output[0]) == output[1];
        require totalSharesBefore + output[0] == to_mathint(totalSharesAfter);
    }
    return output;
}

rule aTokenTransferBalanceTest(uint256 amount, address recipient) {
    env e;
    require e.msg.sender != recipient;

    uint256 assetsBefore = aToken.balanceOf(e, recipient);
        aToken.transfer(e, recipient, amount);
    uint256 assetsAfter = aToken.balanceOf(e, recipient);
    uint256 index = getPoolIndex(e.block.timestamp);

    assert to_mathint(assetsAfter) >= assetsBefore + amount;
    assert to_mathint(assetsAfter) <= assetsBefore + amount + index/RAY() + 1;
}

/// @doc Checks the post state of the _deposit() function.
rule depositOutputChecker(uint256 baseAmount, bool asUnderlying) {
    env e;
    require e.msg.sender != currentContract;
    uint256 minOutput;
    address destination;

    uint256 totalSharesBefore = totalShares();
    uint256 assetsBefore = aToken.balanceOf(e, HDAave);
        openLong(e, baseAmount, minOutput, destination, asUnderlying);
    uint256 totalSharesAfter = totalShares();
    uint256 assetsAfter = aToken.balanceOf(e, HDAave);
    uint256 index = getPoolIndex(e.block.timestamp);

    if(totalSharesBefore == 0) {
        assert totalSharesAfter == baseAmount;
    }
    else {
        //if(asUnderlying) {
        //    assert assetsBefore + baseAmount == to_mathint(assetsAfter);
        //}
        uint256 sharesMinted = mulDivDownAbstractPlus(totalSharesBefore, baseAmount, assetsBefore);
        //uint256 sharePrice = mulDivDownAbstractPlus(baseAmount, ONE18(), sharesMinted);
        assert totalSharesBefore + sharesMinted == to_mathint(totalSharesAfter);
    }
}

/// A helper function to simulate a round trip of open and close a long position.
function LongPositionRoundTripHelper(
    env eOp,  /// openLong() env variable.
    env eCl,  /// closeLong() env variable.
    uint256 baseAmount, /// Amount of tokens to open position with.
    uint256 bondAmount, /// Amount of bonds to redeem (close position).
    uint256 minOutput_open, /// Minimal amount of bonds to receive.
    uint256 minOutput_close, /// Minimal amount of assets to receive.
    address destination_open, /// Address of bonds recipient (open).
    address destination_close, /// Address of assets recipient (close).
    bool asUnderlying_open, /// true - underlying (base token), false - yield token (aToken)
    bool asUnderlying_close, /// true - underlying (base token), false - yield token (aToken)
    uint256 maturityTime /// maturity time (close)
) returns uint256[2] { /// returns[0:1] = [bondsReceived,undelyingRecieved]
    require eOp.msg.sender == eCl.msg.sender;
    require eOp.msg.sender != currentContract;

    uint256 bondsReceived =
        openLong(eOp, baseAmount, minOutput_open, destination_open, asUnderlying_open);

    uint256 assetsRecieved =
        closeLong(eCl, maturityTime, bondAmount, minOutput_close, destination_close, asUnderlying_close);

    uint256[2] result;
    require result[0] == bondsReceived;
    require result[1] == assetsRecieved;

    return result;
}

/// First assert:
/// https://vaas-stg.certora.com/output/41958/d94981d81dff445ea1b426bcc1f67b5a/?anonymousKey=5e9be1e9f27223a8c656055907909be533fb7c57
/// Second assert:
/// https://vaas-stg.certora.com/output/41958/ee5e46675a6f484aab1c82b32dbcf1ba/?anonymousKey=5b02f66971977f3c6d0606ba567dd5cbbdf29a1a
rule whoChangedTotalShares(method f)
filtered{f -> !f.isView} {
    env e;
    calldataarg args;
    uint256 shares1 = totalShares();
    uint256 aTokenBalance1 = aToken.balanceOf(e, currentContract);
        f(e, args);
    uint256 shares2 = totalShares();
    uint256 aTokenBalance2 = aToken.balanceOf(e, currentContract);
    assert shares1 == shares2;
    assert aTokenBalance1 != aTokenBalance2 <=> shares1 != shares2;
}

/// @notice : in progress
/// (In : aToken, Out : aToken)
rule longPositionRoundTrip1() {
    env eOp;
    env eCl;
    uint256 baseAmount; uint256 bondAmount;
    uint256 minOutput_open; uint256 minOutput_close;
    address destination_open; address destination_close;
    uint256 maturityTime;

    /// Probe balances before transaction
    uint256 aTokenBalanceSender_before =
        aToken.balanceOf(eOp, eOp.msg.sender);
    uint256 aTokenBalanceDestOpen_before =
        aToken.balanceOf(eOp, destination_open);
    uint256 aTokenBalanceDestClose_before =
        aToken.balanceOf(eOp, destination_close);

    /// Perform round trip (open aToken -> close aToken)
    uint256[2] result = LongPositionRoundTripHelper(eOp, eCl,
        baseAmount, bondAmount, minOutput_open, minOutput_close,
        destination_open, destination_close, false, false, maturityTime);
    uint256 bondsReceived = result[0];
    uint256 assetsReceived = result[1];

    /// Probe balances after transaction
    uint256 aTokenBalanceSender_after =
        aToken.balanceOf(eCl, eOp.msg.sender);
    uint256 aTokenBalanceDestOpen_after =
        aToken.balanceOf(eCl, destination_open);
    uint256 aTokenBalanceDestClose_after =
        aToken.balanceOf(eCl, destination_close);

    assert minOutput_open <= bondsReceived;
    assert minOutput_close <= assetsReceived;
}

/// @notice : in progress
/// (In : aToken, Out : base token)
rule longPositionRoundTrip2() {
    env eOp;
    env eCl;
    uint256 baseAmount; uint256 bondAmount;
    uint256 minOutput_open; uint256 minOutput_close;
    address destination_open; address destination_close;
    uint256 maturityTime;

    uint256[2] result = LongPositionRoundTripHelper(eOp, eCl,
        baseAmount, bondAmount, minOutput_open, minOutput_close,
        destination_open, destination_close, false, true, maturityTime);

    uint256 bondsReceived = result[0];
    uint256 assetsReceived = result[1];

    assert minOutput_open <= bondsReceived;
    assert minOutput_close <= assetsReceived;
}

/// @doc No action can change the share price for two different checkpoints.
/// @notice [VERIFIED]
rule sharePriceChangesForOnlyOneCheckPoint(method f) {
    env e;
    calldataarg args;
    uint256 _checkpointA;
    uint256 _checkpointB;

    uint128 sharePriceA1 = checkPointSharePrice(_checkpointA);
    uint128 sharePriceB1 = checkPointSharePrice(_checkpointB);
        f(e, args);
    uint128 sharePriceA2 = checkPointSharePrice(_checkpointA);
    uint128 sharePriceB2 = checkPointSharePrice(_checkpointB);

    assert (sharePriceA1 != sharePriceA2 && sharePriceB1 != sharePriceB2)
        => _checkpointA == _checkpointB;
}

/// @doc For every checkpoint, if the share price has been set, it cannot be set again.
/// @notice [VERIFIED]
rule cannotChangeCheckPointSharePriceTwice(uint256 _checkpoint, method f) {
    env e;
    calldataarg args;

    AaveHyperdrive.Checkpoint CP1 = checkPoints(_checkpoint);
        f(e,args);
    AaveHyperdrive.Checkpoint CP2 = checkPoints(_checkpoint);

    assert CP1.sharePrice !=0 => CP1.sharePrice == CP2.sharePrice;
}

rule checkPointPriceIsSetCorrectly(uint256 _checkpoint, method f) {
    env e;
    calldataarg args;

    AaveHyperdrive.Checkpoint CP1 = checkPoints(_checkpoint);
        f(e,args);
    AaveHyperdrive.Checkpoint CP2 = checkPoints(_checkpoint);
    uint256 price = sharePrice(e);

    assert (CP1.sharePrice ==0 && CP2.sharePrice !=0) => to_mathint(CP2.sharePrice) == to_mathint(price);
}

/// @doc integrity rule for 'openLong'
/// - There must be assets in the pool after opening a position.
/// - cannot receive more bonds than registered reserves.
rule openLongIntegrity(uint256 baseAmount) {
    env e;
    uint256 minOutput;
    address destination;
    bool asUnderlying = false;

    setHyperdrivePoolParams();

    AaveHyperdrive.MarketState Mstate = marketState();
    uint128 bondReserves = Mstate.bondReserves;

    uint256 bondsReceived =
        openLong(e, baseAmount, minOutput, destination, asUnderlying);

    uint256 totalShares = totalShares();
    uint256 assets = aToken.balanceOf(e, currentContract);

    assert totalShares > 0 && assets > 0,
        "Assets must have been deposited in the pool after opening a position";

    assert to_mathint(bondsReceived) <= to_mathint(bondReserves),
        "A position cannot be opened with more bonds than bonds reserves";
}

rule openLongReturnsSameBonds(env eOp) {
    uint256 baseAmount; uint256 bondAmount;
    uint256 minOutput_open; uint256 minOutput_close;
    address destination_open1; address destination_close1;
    address destination_open2; address destination_close2;
    uint256 maturityTime1; uint256 maturityTime2;
    bool asUnderlying_open1; bool asUnderlying_open2;

    storage initState = lastStorage;
    uint256 bondsReceived1 = openLong(
        eOp, baseAmount, minOutput_open, destination_open1, asUnderlying_open1
    );
    uint256 bondsReceived2 = openLong(
        eOp, baseAmount, minOutput_open, destination_open2, asUnderlying_open2
    ) at initState;

    assert bondsReceived1 == bondsReceived2, "Received bonds should not depend on destination or asUnderlying";
}

rule profitIsMonotonicForCloseLong(env eCl) {
    uint256 bondAmount;
    uint256 minOutput;
    address destination1; address destination2;
    uint256 maturityTime1; uint256 maturityTime2;
    bool asUnderlying1; bool asUnderlying2;

    storage initState = lastStorage;
    uint256 assetsRecieved1 =
        closeLong(eCl, maturityTime1, bondAmount, minOutput, destination1, asUnderlying1);

    uint256 assetsRecieved2 =
        closeLong(eCl, maturityTime2, bondAmount, minOutput, destination2, asUnderlying2) at initState;

    assert maturityTime1 >= maturityTime2 => assetsRecieved1 <= assetsRecieved2, "Received assets should increase for long position.";
}

rule addAndRemoveSameSharesMeansNoChange(env e) {
    uint256 _contribution;
    uint256 _minApr;
    uint256 _maxApr;
    address _destination;
    bool _asUnderlying;

    uint256 _shares;
    uint256 _minOutput;

    uint256 baseProceeds;
    uint256 withdrawalShares;

    AaveHyperdrive.MarketState Mstate1 = marketState();
    uint256 lpShares = addLiquidity(e, _contribution, _minApr, _maxApr, _destination, _asUnderlying);

    baseProceeds, withdrawalShares = removeLiquidity(e, _shares, _minOutput, _destination, _asUnderlying);
    AaveHyperdrive.MarketState Mstate3 = marketState();

    assert lpShares == withdrawalShares => to_mathint(Mstate1.shareReserves) == to_mathint(Mstate3.shareReserves);
}

/// @doc The sum of longs and shorts should not surpass the total amount of bond reserves
/// @notice: should be turned into an invariant
rule bondsPositionsDontExceedReserves(method f)
filtered{f -> !f.isView} {
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

rule openLongPreservesOutstandingLongs(uint256 baseAmount) {
    env e;
    uint256 minOutput;
    address destination;
    bool asUnderlying;

    setHyperdrivePoolParams();

    uint256 latestCP = require_uint256(e.block.timestamp -
            (e.block.timestamp % checkpointDuration()));

    AaveHyperdrive.MarketState preState = marketState();
    uint128 bondReserves1 = preState.bondReserves;
    uint128 longsOutstanding1 = preState.longsOutstanding;
    uint128 sharePrice1 = checkPointSharePrice(latestCP);

    require sharePrice1*bondReserves1 >= to_mathint(ONE18()*longsOutstanding1);

    uint256 bondsReceived =
        openLong(e, baseAmount, minOutput, destination, asUnderlying);

    AaveHyperdrive.MarketState postState = marketState();
    uint128 bondReserves2 = postState.bondReserves;
    uint128 longsOutstanding2 = postState.longsOutstanding;
    uint128 sharePrice2 = checkPointSharePrice(latestCP);

    assert sharePrice2*bondReserves2 >= to_mathint(ONE18()*longsOutstanding2);
}

/// @doc Closing a long position at maturity should return the same number of tokens as the number of bonds.
rule closeLongAtMaturity(uint256 bondAmount) {
    env e;
    uint256 minOutput;
    address destination;
    bool asUnderlying;
    uint256 maturityTime;

    setHyperdrivePoolParams();
    uint256 price = sharePrice(e);
    require price > initialSharePrice() && to_mathint(price) <= 2*ONE18();
    //require totalShares() != 0;

    uint256 assetsRecieved =
        closeLong(e, maturityTime, bondAmount, minOutput, destination, asUnderlying);

    assert maturityTime >= e.block.timestamp => assetsRecieved == bondAmount;
}

/// @doc calling checkpoint() twice on two checkpoint times cannot change the outstanding posiitons twice
/// @notice : Violated because it's not assumed there aren't 'holes' in checkpoints.
rule doubleCheckpointHasNoEffect(uint256 time1, uint256 time2) {
    env e;
    uint128 Longs1 = stateLongs();
    uint128 Shorts1 = stateShorts();
        checkpoint(e, time1);
    uint128 Longs2 = stateLongs();
    uint128 Shorts2 = stateShorts();
        checkpoint(e, time2);
    uint128 Longs3 = stateLongs();
    uint128 Shorts3 = stateShorts();

    assert !(Longs1 == Longs2 && Shorts1 == Shorts2) =>
        (Longs2 == Longs3 && Shorts2 == Shorts3),
        "If the outstanding bonds were changed by a first checkpoint, they cannot be changed by a second";
}

rule checkPointCannotChangePoolPresentValue(uint256 time) {
    env e;
    setHyperdrivePoolParams();
    uint256 _sharePrice = require_uint256(2*ONE18());

    /// Calc present value:
    uint256 value1 = getPresentValue(e, _sharePrice);
    /// Checkpoint:
        checkpoint(e, time);
    /// Calc present value:
    uint256 value2 = getPresentValue(e, _sharePrice);

    assert value1 == value2;
}

/// Verified
invariant NoFutureTokens(uint256 AssetId, env e)
    timeByID(AssetId) > e.block.timestamp + positionDuration() => totalSupplyByToken(AssetId) == 0
    {
        preserved with (env eP) {
            require e.block.timestamp == eP.block.timestamp;
        }
    }

/// @doc Tokens could only be minted at checkpoint time intervals.
invariant NoTokensBetweenCheckPoints(uint256 AssetId)
    (timeByID(AssetId) - positionDuration()) % checkpointDuration() !=0 => totalSupplyByToken(AssetId) == 0 
    {
        preserved{
            //setHyperdrivePoolParams(); 
            require checkpointDuration() !=0;
        }
    }

/// @doc If there are shares in the pool, there must be underlying assets.
invariant SharesNonZeroAssetsNonZero(env e)
    totalShares() !=0 => aToken.balanceOf(e, HDAave) != 0
    {
        preserved with (env eP) {
            setHyperdrivePoolParams();
            require eP.block.timestamp == e.block.timestamp;
            require totalShares() >= ONE18();
            require aToken.balanceOf(eP, HDAave) >= ONE18();
        }
    }

/// @doc The sum of withdrawal shares for all accounts is equal to the shares which are ready to withdraw
/// Violated on removeLiquidity : need to investigate path.
invariant SharesReadyToBeRedeemedAreBounded()
    totalWithdrawalShares() >= readyToRedeemShares() 
    {
        preserved{setHyperdrivePoolParams();}
    }

/// https://vaas-stg.certora.com/output/41958/9c6cd4e94b6948a1aa8c760877422a2c/?anonymousKey=b8754681d6883c5a3eb1c3ab57552ebdba610067
/// @doc The fixed interest (r+1) must never be smaller than 1.
rule FixedInterestLargerThanOne(method f) filtered{f -> !f.isView} {
    env e;
    calldataarg args;
    setHyperdrivePoolParams();
    require curveFixedInterest() >= to_mathint(ONE18());
        f(e,args);
    assert curveFixedInterest() >= to_mathint(ONE18());
}

/// @doc It's impossible to get to a state where both shares and bonds are empty
/// @dev maybe it's possible if all liquidity has been withdrawan?
/*
rule cannotCompletelyDepletePool(method f) filtered{f -> !f.isView} {
    env e;
    calldataarg args;
    setHyperdrivePoolParams();
    require require_uint256(stateBondReserves()) >= ONE18() && require_uint256(stateShareReserves()) >= ONE18();
        f(e,args);
    assert !(stateBondReserves() == 0 && stateShareReserves() == 0);
}
*/

rule LongAverageMaturityTimeIsBounded(method f) 
filtered{f -> !f.isView} {
    env e;
    mathint Time = to_mathint(e.block.timestamp);
    mathint duration = positionDuration();
    calldataarg args;

    setHyperdrivePoolParams();

    AaveHyperdrive.MarketState Mstate1 = marketState();
    mathint LongAvgTime1 = to_mathint(Mstate1.longAverageMaturityTime);
        f(e, args);
    AaveHyperdrive.MarketState Mstate2 = marketState();
    mathint LongAvgTime2 = to_mathint(Mstate2.longAverageMaturityTime);

    require LongAvgTime1 >= Time && LongAvgTime1 <= Time + duration;
    assert LongAvgTime2 >= Time && LongAvgTime2 <= Time + duration;
}

/// https://vaas-stg.certora.com/output/41958/72b2e377545f4c71aefdb613bb6ccf05/?anonymousKey=41c772576393e67ba8e07cc739c3e302b74aa353
invariant SharePriceAlwaysGreaterThanInitial(uint256 checkpointTime)
    checkPointSharePrice(checkpointTime) == 0 || to_mathint(checkPointSharePrice(checkpointTime)) >= to_mathint(initialSharePrice())
    {
        preserved{setHyperdrivePoolParams();}
    }

invariant SharePriceCannotDecreaseInTime(uint256 checkpointTime1, uint256 checkpointTime2)
    checkpointTime1 < checkpointTime2 =>
        checkPointSharePrice(checkpointTime1) <= checkPointSharePrice(checkpointTime2)
    {
        preserved {setHyperdrivePoolParams();}
    }


/// @doc There should always be more aTokens (assets) than number of shares
/// otherwise, the share price will decrease (or less than 1).
invariant aTokenBalanceGEToShares(env e)
    totalShares() <= aToken.balanceOf(e, currentContract)
    {
        preserved with (env eP) {
            require eP.block.timestamp == e.block.timestamp;
        }
    }

invariant ShareReservesBackLongs()
    stateShareReserves() >= stateLongs()
    {
        preserved{setHyperdrivePoolParams();}
    }

/// @doc The sum of longs tokens is greater or equal to the outstanding longs.
/// @notice The sum is not necessarily equal to the outstanding count.
invariant SumOfLongsGEOutstanding()
    sumOfLongs() >= to_mathint(stateLongs());

/// @doc The sum of shorts tokens is greater or equal to the outstanding shorts.
/// @notice The sum is not necessarily equal to the outstanding count.
invariant SumOfShortsGEOutstanding()
    sumOfShorts() >= to_mathint(stateShorts());