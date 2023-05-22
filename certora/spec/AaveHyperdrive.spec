import "./erc20.spec";
import "./MathSummaries.spec";
import "./Sanity.spec";
import "./HyperdriveStorage.spec";
//import "./Fees.spec";

using AaveHyperdrive as HDAave;
using DummyATokenA as aToken;
using Pool as pool;

use rule sanity;

methods {
    function _.mint(address,address,uint256,uint256) external => DISPATCHER(true);
    function _.burn(address,address,uint256,uint256) external => DISPATCHER(true);

    function aToken.UNDERLYING_ASSET_ADDRESS() external returns (address) envfree;
    function aToken.balanceOf(address) external returns (uint256);
    function pool.liquidityIndex(address,uint256) external returns (uint256) envfree;
    function HDAave.totalShares() external returns (uint256) envfree;

    /// Fee calculations summaries
    function HDAave.MockCalculateFeesOutGivenSharesIn(uint256,uint256,uint256,uint256,uint256) internal returns(AaveHyperdrive.HDFee memory) => NONDET;
    function HDAave.MockCalculateFeesOutGivenBondsIn(uint256,uint256,uint256,uint256) internal returns(AaveHyperdrive.HDFee memory) => NONDET;
    function HDAave.MockCalculateFeesInGivenBondsOut(uint256,uint256,uint256,uint256) internal returns(AaveHyperdrive.HDFee memory) => NONDET;
    /*
    function HDAave.MockCalculateFeesOutGivenSharesIn(uint256 a,uint256 b ,uint256 c ,uint256 d,uint256 e) internal returns(AaveHyperdrive.HDFee memory) =>
        CVLFeesOutGivenSharesIn(a,b,c,d,e);
    function HDAave.MockCalculateFeesOutGivenBondsIn(uint256 a, uint256 b,uint256 c, uint256 d) internal returns(AaveHyperdrive.HDFee memory) =>
        CVLFeesOutGivenAmountsIn(a,b,c,d);
    function HDAave.MockCalculateFeesInGivenBondsOut(uint256 a, uint256 b, uint256 c, uint256 d) internal returns(AaveHyperdrive.HDFee memory) =>
        CVLFeesOutGivenAmountsIn(a,b,c,d);
    */
}

definition RAY() returns uint256 = 10^27;

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
    require index >= RAY();
}

function getPoolIndex(uint256 timestamp) returns uint256 {
    return pool.liquidityIndex(aToken.UNDERLYING_ASSET_ADDRESS(),timestamp);
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
    uint256 totalSharesAfter = HDAave.totalShares();
    uint256 assetsAfter = aToken.balanceOf(e, HDAave);

    if(totalSharesBefore == 0) {
        require baseAmount == output[0];
        require ONE18() == output[1];
    }
    else {
        if(asUnderlying) {
            require baseAmount > 0 => assetsBefore < assetsAfter;
        }
        else {
            require assetsBefore + baseAmount == to_mathint(assetsAfter);
        }
        require mulDivDownAbstractPlus(totalSharesBefore, baseAmount, assetsBefore) == output[0];
        require mulDivDownAbstractPlus(baseAmount, ONE18(), output[0]) == output[1];
        require totalSharesBefore + output[0] == to_mathint(totalSharesAfter);
    }
    return output;
}

/// @doc Checks the post state of the _deposit() function.
/// https://vaas-stg.certora.com/output/41958/965e09d01a7e4fe0884b83fcccbfa71d/?anonymousKey=2f8a8fc5b978cfae5d16368b4f91e8d9f42a8b7a
rule depositOutputChecker(uint256 baseAmount, bool asUnderlying) {
    env e;
    require e.msg.sender != currentContract;
    uint256 minOutput;
    address destination;

    uint256 totalSharesBefore = HDAave.totalShares();
    uint256 assetsBefore = aToken.balanceOf(e, HDAave);
        openLong(e, baseAmount, minOutput, destination, asUnderlying);
    uint256 totalSharesAfter = HDAave.totalShares();
    uint256 assetsAfter = aToken.balanceOf(e, HDAave);
    uint256 index = getPoolIndex(e.block.timestamp);

    if(totalSharesBefore == 0) {
        assert totalSharesAfter == baseAmount;
    }
    else {
        if(asUnderlying) {
            assert assetsBefore + baseAmount == to_mathint(assetsAfter);
        }
        else {
            assert assetsBefore + baseAmount + 1 >= to_mathint(assetsAfter);
            assert assetsBefore + baseAmount - index/RAY() <= to_mathint(assetsAfter);
        }
        //uint256 sharesMinted = mulDivDownAbstractPlus(totalSharesBefore, baseAmount, assetsBefore);
        //uint256 sharePrice = mulDivDownAbstractPlus(baseAmount, ONE18(), sharesMinted);
        //assert totalSharesBefore + sharesMinted == to_mathint(totalSharesAfter);
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
    uint256 shares1 = HDAave.totalShares();
    uint256 aTokenBalance1 = aToken.balanceOf(e, currentContract);
        f(e, args);
    uint256 shares2 = HDAave.totalShares();
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

/// @doc integrity rule for 'openLong'
/// - cannot receive more bonds than registered reserves.
rule openLongIntegrity(uint256 baseAmount) {
    env e;
    uint256 minOutput;
    address destination;
    bool asUnderlying;

    AaveHyperdrive.MarketState Mstate = marketState();
    uint128 bondReserves = Mstate.bondReserves;

    uint256 bondsReceived =
        openLong(e, baseAmount, minOutput, destination, asUnderlying);

    assert to_mathint(bondsReceived) <= to_mathint(bondReserves),
        "A position cannot be opened with more bonds than bonds reserves";
}

rule profitIsMonotonic(method f) {
    env eOp1;
    env eCl1;
    env eOp2;
    env eCl2;

    require(eOp1.block.timestamp == eOp2.block.timestamp);
    require(eCl1.block.timestamp == eCl2.block.timestamp);

    uint256 baseAmount; uint256 bondAmount;
    uint256 minOutput_open; uint256 minOutput_close;
    address destination_open1; address destination_close1;
    address destination_open2; address destination_close2;
    uint256 maturityTime1;
    uint256 maturityTime2;

    uint256[2] result1 = LongPositionRoundTripHelper(eOp1, eCl1,
        baseAmount, bondAmount, minOutput_open, minOutput_close,
        destination_open1, destination_close1, false, true, maturityTime1);
    uint256[2] result2 = LongPositionRoundTripHelper(eOp2, eCl2,
        baseAmount, bondAmount, minOutput_open, minOutput_close,
        destination_open2, destination_close2, false, true, maturityTime2);

    uint256 bondsReceived1 = result1[0];
    uint256 assetsReceived1 = result1[1];
    uint256 bondsReceived2 = result2[0];
    uint256 assetsReceived2 = result2[1];

    assert maturityTime1 < maturityTime2 => bondsReceived1 <= bondsReceived2;
    assert maturityTime1 < maturityTime2 => assetsReceived1 <= assetsReceived2;
}

rule addAndRemoveSameSharesNoChangeOnShares(env e)
{
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

    // assert to_mathint(Mstate1.bondReserves) == to_mathint(Mstate3.bondReserves);
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

/// @doc If there are shares in the pool, there must be underlying assets.
invariant SharesNonZeroAssetsNonZero(env e)
    HDAave.totalShares() !=0 => aToken.balanceOf(e, HDAave) != 0
    {
        preserved with (env eP) {
            setHyperdrivePoolParams();
            require eP.block.timestamp == e.block.timestamp;
            require HDAave.totalShares() >= ONE18();
            require aToken.balanceOf(eP, HDAave) >= ONE18();
        }
    }

/// @doc bond reserves / share reserves >= initial share price
/// https://vaas-stg.certora.com/output/41958/965e09d01a7e4fe0884b83fcccbfa71d/?anonymousKey=2f8a8fc5b978cfae5d16368b4f91e8d9f42a8b7a
rule maxCurveTradeIntegrity(method f) filtered{f -> !f.isView} {
    env e;
    calldataarg args;
    setHyperdrivePoolParams();
    require (stateBondReserves() * ONE18()) / initialSharePrice() >= to_mathint(stateShareReserves());
        f(e,args);
    assert (stateBondReserves() * ONE18()) / initialSharePrice()  >= to_mathint(stateShareReserves());
}

/// @doc It's impossible to get to a state where both shares and bonds are empty
/// @dev maybe it's possible if all liquidity has been withdrawan?
/// https://vaas-stg.certora.com/output/41958/ae9b37fd55944155b4f513bb6fda1101/?anonymousKey=fc7e4187dde6bfeed7adbcb6d830747a6360cc3e
rule CannotCompletelyDepletePool(method f) filtered{f -> !f.isView} {
    env e;
    calldataarg args;
    setHyperdrivePoolParams();
    require require_uint256(stateBondReserves()) >= ONE18() && require_uint256(stateShareReserves()) >= ONE18();
        f(e,args);
    assert !(stateBondReserves() == 0 && stateShareReserves() == 0);
}

/// https://vaas-stg.certora.com/output/41958/72b2e377545f4c71aefdb613bb6ccf05/?anonymousKey=41c772576393e67ba8e07cc739c3e302b74aa353
invariant SharePriceCannotDecrease(uint256 checkpointTime)
    checkPointSharePrice(checkpointTime) == 0 || to_mathint(checkPointSharePrice(checkpointTime)) >= to_mathint(initialSharePrice())
    {
        preserved{setHyperdrivePoolParams();}
    }

/// @doc There should always be more aTokens (assets) than number of shares
/// otherwise, the share price will decrease (or less than 1).
invariant aTokenBalanceGEToShares(env e)
    HDAave.totalShares() <= aToken.balanceOf(e, currentContract)
    {
        preserved with (env eP) {
            require eP.block.timestamp == e.block.timestamp;
        }
    }

/// marketState.longsOutstanding = sum of open longs.
/// marketState.shortsOutstanding = sum of open shorts.