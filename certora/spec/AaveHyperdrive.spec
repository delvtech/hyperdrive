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

/// Aave pool aToken indices
definition indexA() returns uint256 = require_uint256(RAY()*2);
definition indexB() returns uint256 = require_uint256((RAY()*125)/100);
/// Maximum share price of the Hyperdrive
definition MaxSharePrice() returns mathint = ONE18() * 1000;

definition isInitialize(method f) returns bool = 
    f.selector == sig:initialize(uint256,uint256,address,bool).selector;

/// @dev Under-approximation of the pool parameters (based on developers' test)
/// @notice Use only to find violations!
function setHyperdrivePoolParams() {
    require initialSharePrice() == ONE18();
    require timeStretch() == 45071688063194104; /// 5% APR
    require checkpointDuration() == 86400;
    require positionDuration() == 31536000;
    require updateGap() == 1000;
    /// Realistic conditions
    require require_uint256(stateShareReserves()) == ONE18();
    require require_uint256(stateBondReserves()) >= ONE18();
    /// Alternative
    //require curveFee() == require_uint256(ONE18() / 10);
    //require flatFee() == require_uint256(ONE18() / 10);
    //require governanceFee() == require_uint256(ONE18() / 2);
    ///
    //require curveFee() <= require_uint256(ONE18() / 10);
    //require flatFee() <= require_uint256(ONE18() / 10);
    //require governanceFee() <= require_uint256(ONE18() / 2);
}
/*
function HyperdriveInvariants(env e) {
    requireInvariant LongAverageMaturityTimeIsBounded(e);
    requireInvariant ShortAverageMaturityTimeIsBounded(e);
    requireInvariant SpotPriceIsLessThanOne();
    requireInvariant WithdrawalSharesGEReadyShares();
    requireInvariant SumOfShortsGEOutstanding();
    requireInvariant SumOfLongsGEOutstanding();
}
*/

/// A hook for loading the Aave pool liquidity index
hook Sload uint256 index Pool.liquidityIndex[KEY address token][KEY uint256 timestamp] STORAGE {
    /// @WARNING : UNDER-APPROXIMATION!
    /// @notice : to simplify the SMT formulas, we assume a specific value for the index.
    /// so in general, the index as a function of time is actually a constant.
    require index == indexA();// || index == indexB();
    //require index >= RAY();
}

/// A hook for loading the checkpoint prices
/// @notice To focus on realistic values, we assume the checkpoint was either not set
/// (zero price), or that the price is bounded between 1 and 100.
hook Sload uint128 price currentContract._checkpoints[KEY uint256 timestamp].sharePrice STORAGE {
    require (price == 0) || (require_uint256(price) >= ONE18() && to_mathint(price) <= MaxSharePrice());
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

/// Checks the post state of the _deposit() function.
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

/// No action can change the share price for two different checkpoints.
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

/// For every checkpoint, if the share price has been set, it cannot be set again.
/// @notice [VERIFIED]
rule cannotChangeCheckPointSharePriceTwice(uint256 _checkpoint, method f) {
    env e;
    calldataarg args;

    AaveHyperdrive.Checkpoint CP1 = checkPoints(_checkpoint);
        f(e,args);
    AaveHyperdrive.Checkpoint CP2 = checkPoints(_checkpoint);

    assert CP1.sharePrice !=0 => CP1.sharePrice == CP2.sharePrice;
}

/// No function can change the total supply of two different tokens at the same time.
/// @notice the only exception to this rule is 
/// the function removeLiqudity() that can change both LP tokens types only!
rule onlyOneTokenTotalSupplyChangesAtATime(method f, uint256 assetID1, uint256 assetID2) 
filtered{ f -> !f.isView } {
    env e;
    calldataarg args;

    uint256 supply1_before = totalSupplyByToken(assetID1);
    uint256 supply2_before = totalSupplyByToken(assetID2);
        f(e, args);
    uint256 supply1_after = totalSupplyByToken(assetID1);
    uint256 supply2_after = totalSupplyByToken(assetID2);

    bool bothSuppliesChanged = supply1_before != supply1_after && supply2_before != supply2_after;

    if (isRemoveLiq(f)) {
        assert bothSuppliesChanged => (
            (assetID1 == assetID2) || 
            (assetID1 == LP_ASSET_ID() && assetID2 == WITHDRAWAL_SHARE_ASSET_ID()) ||
            (assetID2 == LP_ASSET_ID() && assetID1 == WITHDRAWAL_SHARE_ASSET_ID()));
    }
    else {
        assert bothSuppliesChanged => assetID1 == assetID2;
    }
}

/// Violated
rule checkPointPriceIsSetCorrectly(uint256 _checkpoint) {
    env e;
    calldataarg args;
    setHyperdrivePoolParams();

    mathint price1 = to_mathint(sharePrice(e));
    mathint preSharePrice = checkPointSharePrice(_checkpoint);
        checkpoint(e, args);
    mathint postSharePrice = checkPointSharePrice(_checkpoint);
    mathint price2 = to_mathint(sharePrice(e));

    assert (preSharePrice ==0 && postSharePrice !=0) => 
       (postSharePrice <= max(price1,price2) && postSharePrice >= min(price1,price2));
}

/// @notice integrity rule for 'openLong'
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

rule openLongPreservesOutstandingLongs(uint256 baseAmount) {
    env e;
    uint256 minOutput;
    address destination;
    bool asUnderlying;

    setHyperdrivePoolParams();
    /// Not proven yet, used for filtering counter-examples
    requireInvariant aTokenBalanceGEToShares(e);
    requireInvariant SumOfShortsGEOutstanding();
    requireInvariant SumOfLongsGEOutstanding();

    uint256 latestCP = require_uint256(e.block.timestamp -
            (e.block.timestamp % checkpointDuration()));

    AaveHyperdrive.MarketState preState = marketState();
    uint128 bondReserves1 = preState.bondReserves;
    uint128 longsOutstanding1 = preState.longsOutstanding;
    uint256 sharePrice1 = sharePrice(e);
    require to_mathint(checkPointSharePrice(latestCP)) == to_mathint(sharePrice1);

    require mulUpWad(sharePrice1, bondReserves1) >= assert_uint256(longsOutstanding1);

    uint256 bondsReceived =
        openLong(e, baseAmount, minOutput, destination, asUnderlying);

    AaveHyperdrive.MarketState postState = marketState();
    uint128 bondReserves2 = postState.bondReserves;
    uint128 longsOutstanding2 = postState.longsOutstanding;
    uint256 sharePrice2 = sharePrice(e);

    assert mulUpWad(sharePrice2, bondReserves2) >= assert_uint256(longsOutstanding2);
}

/// Closing a long position at maturity should return the same number of tokens as the number of bonds.
rule closeLongAtMaturity(uint256 bondAmount) {
    env e;
    uint256 minOutput;
    address destination;
    bool asUnderlying;
    uint256 maturityTime;

    setHyperdrivePoolParams();

    uint256 assetsRecieved =
        closeLong(e, maturityTime, bondAmount, minOutput, destination, asUnderlying);

    assert maturityTime >= e.block.timestamp => assetsRecieved == bondAmount;
}

/// calling checkpoint() twice on two checkpoint times cannot change the outstanding posiitons twice
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

/// The present value of the pool should not change after 'checkpointing'
/// @notice Trivially violated since the present value function is summarized.
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

/// Tokens could be minted at a time that corresponds to position duration time in the future
/// (since the latest checkpoint)
/// [VERIFIED]
rule mintingTokensOnlyAtMaturityTime(method f, uint256 AssetId) 
filtered{ f -> !f.isView } {
    /// We are only concerned with longs and shorts tokens.
    mathint prefix = prefixByID(AssetId);
    require prefix == 1 || prefix == 2;
    
    env e;
    calldataarg args;
    /// Avoid dividing by zero
    require checkpointDuration() !=0;
    /// Maturity time = latest checkpoint + position duration
    mathint maturityTime = 
        e.block.timestamp - (e.block.timestamp % checkpointDuration()) + positionDuration();
    uint256 supplyBefore = totalSupplyByToken(AssetId);
        f(e, args);
    uint256 supplyAfter = totalSupplyByToken(AssetId);

    assert supplyAfter > supplyBefore => timeByID(AssetId) == maturityTime;
}

/// @notice If the checkpoint share price was set by a function, so all matured positions
/// of that checkpoint should have been removed from the outstanding longs/shorts. 
rule settingThePriceAlsoClosesMaturedPositions(uint256 checkpointTime, method f) 
filtered{ f -> !f.isView && f.selector != sig:checkpoint(uint256).selector } {
    env e;
    calldataarg args;

    mathint price1 = checkPointSharePrice(checkpointTime);
    mathint longsOutstanding1 = stateLongs();
    mathint shortsOutstanding1 = stateShorts();
        f(e, args);
    mathint price2 = checkPointSharePrice(checkpointTime);
    mathint longsOutstanding2 = stateLongs();
    mathint shortsOutstanding2 = stateShorts();
    /// Require that the price has changed (or set to non-zero).
    require price1 ==0 && price2 !=0;

    /// Assume that there are longs/shorts tokens for that checkpoint time
    uint256 AssetId;
    mathint prefix = prefixByID(AssetId);
    require prefix == 1 || prefix == 2;
    require timeByID(AssetId) == to_mathint(checkpointTime);
    require checkpointTime <= e.block.timestamp; // Longs/shorts have matured
    require totalSupplyByToken(AssetId) > 0;

    assert longsOutstanding1 != longsOutstanding2 || shortsOutstanding1 == shortsOutstanding2,
        "The outstanding shorts or longs must have been updated (virtually closing the matured)";
}

/// Verified
invariant NoFutureTokens(uint256 AssetId, env e)
    timeByID(AssetId) > e.block.timestamp + positionDuration() => totalSupplyByToken(AssetId) == 0
    {
        preserved with (env eP) {
            require e.block.timestamp == eP.block.timestamp;
        }
    }

/// Long and shorts tokens could only be minted at checkpoint time intervals.
invariant NoTokensBetweenCheckPoints(uint256 AssetId)
    (
        AssetId != WITHDRAWAL_SHARE_ASSET_ID() && 
        AssetId != LP_ASSET_ID() && 
        (timeByID(AssetId) - positionDuration()) % checkpointDuration() !=0
    )
        => totalSupplyByToken(AssetId) == 0 
    {
        preserved{
            setHyperdrivePoolParams(); 
            require checkpointDuration() !=0;
        }
    }

/// If there are shares in the pool, there must be underlying assets.
/// Violated for removeLiquidity:
/// https://vaas-stg.certora.com/output/41958/31864532f046423ea1f0e0988ebe5e1a/?anonymousKey=63f56d320526ee9dc6552956c574822f476e7273
invariant SharesNonZeroAssetsNonZero(env e)
    totalShares() !=0 => aToken.balanceOf(e, HDAave) != 0
    {
        preserved with (env eP) {
            setHyperdrivePoolParams();
            require eP.block.timestamp == e.block.timestamp;
            require totalShares() >= ONE18();
        }
    }

/// The ready to redeem shares cannot exceed the total withdrawal shares.
/// [VERIFIED]
invariant WithdrawalSharesGEReadyShares()
    totalWithdrawalShares() >= readyToRedeemShares();

/// The Spot price p = [(mu * z / y) ^ tau] must be smaller than one.
/// Violated
/// https://vaas-stg.certora.com/output/41958/794fadd9600c4a728e23eca6712b6b66/?anonymousKey=a3bc9d0843c440ba8c78610f331c921eb65744e9
invariant SpotPriceIsLessThanOne()
    stateBondReserves() !=0 => mulDivDownAbstractPlus(stateShareReserves(), initialSharePrice(), stateBondReserves()) <= ONE18()
    filtered{f -> isOpenShort(f)}
    {
        preserved with (env e) {
            setHyperdrivePoolParams();
            require sharePrice(e) >= initialSharePrice(); 
        }
    }

/// It's impossible to get to a state where both shares and bonds are empty
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

/// The yield from closing a bond should be linearly bounded by the time passed since the position was opened.
/// @notice The rule is still in progress.
/// Need to think how to take into account the curve share proceeds
rule closeLongYieldIsBoundedByTime(uint256 openTimeStamp) {
    env e;
    require e.block.timestamp >= 10000000;
    require openTimeStamp <= e.block.timestamp;
    setHyperdrivePoolParams();
    
    uint256 minOutput;
    address destination;
    uint256 bondAmount;
    uint256 latestCP = require_uint256(openTimeStamp - (openTimeStamp % checkpointDuration()));

    /// This is the outcome of opening a long at `openTimeStamp`:
    uint256 maturityTime = require_uint256(latestCP + positionDuration());
    require openTimeStamp >= latestCP && to_mathint(openTimeStamp) < latestCP + checkpointDuration();
    uint256 timeElapsed = require_uint256(min(to_mathint(positionDuration()), e.block.timestamp - openTimeStamp));

    /// Calling closeLong 
    uint256 assetsRecieved =
        closeLong(e, maturityTime, bondAmount, minOutput, destination, false);

    /// The amount of assets received should be (time elapsed / positionDuration) * bonds
    assert assetsRecieved <= mulDivUpAbstractPlus(timeElapsed, bondAmount, positionDuration());
}

/// @notice The average maturity time should always be between the current time stamp and the time stamp + duration.
/// In other words, matured positions should not be taken into account in the average time.
invariant LongAverageMaturityTimeIsBounded(env e)
    (stateLongs() == 0 => AvgMTimeLongs() == 0) &&
    (stateLongs() != 0 => 
        AvgMTimeLongs() >= e.block.timestamp * ONE18() &&
        AvgMTimeLongs() <= ONE18()*(e.block.timestamp + positionDuration()))
    {
        preserved with (env eP) {
            require e.block.timestamp == eP.block.timestamp;
            setHyperdrivePoolParams();
            requireInvariant SumOfLongsGEOutstanding();
        }
    }


/// @notice The average maturity time should always be between the current time stamp and the time stamp + duration.
/// In other words, matured positions should not be taken into account in the average time.
invariant ShortAverageMaturityTimeIsBounded(env e)
    (stateShorts() == 0 => AvgMTimeShorts() == 0) &&
    (stateShorts() != 0 => 
        AvgMTimeShorts() >= e.block.timestamp * ONE18() &&
        AvgMTimeShorts() <= ONE18()*(e.block.timestamp + positionDuration()))
    {
        preserved with (env eP) {
            require e.block.timestamp == eP.block.timestamp;
            setHyperdrivePoolParams();
            requireInvariant SumOfShortsGEOutstanding();
        }
    }

/// Tadeas trying to verify ShortAverageMaturityTimeIsBounded using split and rule
/// Very similar violation here:
/// https://vaas-stg.certora.com/output/40577/42200a0dbfc64327b94bf77475fc94f8/?anonymousKey=f8c90f7eba1651774b848c4aa436e18058511e38
///     - e.block.timestamp = *   ... is arbitrary
///     - AvgMTimeShorts()  = *   ... is arbitrary
rule shortAverageMaturityTimeIsBoundedAfterOpenShort2(env e)
{
    setHyperdrivePoolParams();

    require stateShorts() == 0 && AvgMTimeShorts() == 0;

    uint256 baseAmount;
    uint256 maxDeposit;
    address destination;
    bool asUnderlying;

    // TODO: Consider limiting this short to be "normal"
    openShort(e, baseAmount, maxDeposit, destination, asUnderlying);

    assert stateShorts() == 0 => AvgMTimeShorts() == 0;
    assert stateShorts() != 0 =>
        AvgMTimeShorts() >= e.block.timestamp * ONE18() &&
        AvgMTimeShorts() <= ONE18()*(e.block.timestamp + positionDuration());
}

/// @notice The share price cannot go below the initial price.
invariant SharePriceAlwaysGreaterThanInitial(env e)
    sharePrice(e) >= initialSharePrice()
    {
        preserved with (env eP) {
            require eP.block.timestamp == e.block.timestamp;
            requireInvariant SumOfLongsGEOutstanding();
            requireInvariant SumOfShortsGEOutstanding();
            requireInvariant WithdrawalSharesGEReadyShares();
            requireInvariant SpotPriceIsLessThanOne();
            setHyperdrivePoolParams();
        }
    }

rule SharePriceCannotDecreaseAfterOperation(method f) {
    env e;
    calldataarg args;
    uint256 sharePriceBefore = sharePrice(e);
        f(e, args);
    uint256 sharePriceAfter = sharePrice(e);

    assert sharePriceAfter >= sharePriceBefore;
}

/// There should always be more aTokens (assets) than number of shares
/// otherwise, the share price will decrease (or less than 1).
invariant aTokenBalanceGEToShares(env e)
    totalShares() <= aToken.balanceOf(e, currentContract)
    filtered{f -> isCloseLong(f)}
    {
        preserved with (env eP) {
            require eP.block.timestamp == e.block.timestamp;
            requireInvariant SumOfLongsGEOutstanding();
            requireInvariant SumOfShortsGEOutstanding();
            requireInvariant WithdrawalSharesGEReadyShares();
            requireInvariant SpotPriceIsLessThanOne();
            setHyperdrivePoolParams();
        }
    }

/// The sum of longs tokens is greater or equal to the outstanding longs.
/// @notice The sum is not necessarily equal to the outstanding count.
/// @notice [VERIFIED]
invariant SumOfLongsGEOutstanding()
    sumOfLongs() >= to_mathint(stateLongs());

/// The sum of shorts tokens is greater or equal to the outstanding shorts.
/// @notice The sum is not necessarily equal to the outstanding count.
/// @notice [VERIFIED]
invariant SumOfShortsGEOutstanding()
    sumOfShorts() >= to_mathint(stateShorts());
    
/// There are always enough shares to cover all long positions
invariant ShareReservesCoverLongs(env e)
    mulDownWad(require_uint256(stateShareReserves()), sharePrice(e)) >= require_uint256(stateLongs())
    filtered{f -> isOpenShort(f)}
    {
        preserved with (env eP) {
            require e.block.timestamp == eP.block.timestamp;
            setHyperdrivePoolParams();
            requireInvariant SpotPriceIsLessThanOne();
        }
    }

/// If there are not shares in the pool, then there are only shorts in the pool (no longs)
invariant NoSharesNoShorts()
    stateShareReserves() == 0 => sumOfLongs() == 0
    filtered{f -> isCloseShort(f) || isOpenLong(f)}
    {
        preserved {
            requireInvariant SumOfLongsGEOutstanding();
            requireInvariant SumOfShortsGEOutstanding();
        }
    }

/// Timeout
rule shortRoundTripSameBaseVolume(uint256 bondAmount) {
    env e;
    uint256 maxDeposit;
    address destination;
    bool asUnderlying;
    uint256 minOutput;
    
    setHyperdrivePoolParams();
    
    uint256 maturityTime = 
        require_uint256(e.block.timestamp - (e.block.timestamp % checkpointDuration()) + positionDuration());
    
    AaveHyperdrive.MarketState Mstate = marketState();
    uint128 baseVolumeBefore = Mstate.shortBaseVolume;
        uint256 userDeposit = openShort(e, bondAmount, maxDeposit, destination, asUnderlying);
        uint256 baseRewards = closeShort(e, maturityTime, bondAmount, minOutput, destination, asUnderlying);
    uint128 baseVolumeAfter = Mstate.shortBaseVolume;

    assert baseVolumeAfter == baseVolumeBefore;
    assert baseRewards <= userDeposit;
}

/// Timeout
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

/// Violated
/// https://prover.certora.com/output/41958/f61a641de2d446d7875f24f21fac5e07/?anonymousKey=b972ae7327581893456828151a2f743bb35299df
rule openShortMustPay(uint256 bondAmount) {
    env e1; require e1.msg.sender != currentContract;
    
    uint256 maxDeposit;
    address destination;
    setHyperdrivePoolParams();
    require bondAmount >= 10^6;
    require sharePrice(e1) >= ONE18();
    requireInvariant SpotPriceIsLessThanOne();    
    require e1.block.timestamp == 10^6;

    uint256 balance1 = aToken.balanceOf(e1, e1.msg.sender);
        uint256 traderDeposit = openShort(e1, bondAmount, maxDeposit, destination, false);
    uint256 balance2 = aToken.balanceOf(e1, e1.msg.sender);

    assert traderDeposit !=0;
}