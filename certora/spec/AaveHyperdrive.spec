import "./erc20.spec";
import "./MathSummaries.spec";
import "./Sanity.spec";
import "./HyperdriveStorage.spec";

using AaveHyperdrive as HDAave;
using DummyATokenA as aToken;

use rule sanity;
      
methods {
    function _.mint(address,address,uint256,uint256) external => DISPATCHER(true);
    function _.burn(address,address,uint256,uint256) external => DISPATCHER(true);
    
    function aToken.balanceOf(address) external returns (uint256);

    function HDAave.totalShares() external returns (uint256) envfree;
    function HDAave.MockCalculateFeesOutGivenSharesIn(uint256 x,uint256,uint256,uint256,uint256) internal returns(AaveHyperdrive.HDFee memory) => Foo(x);
    function HDAave.MockCalculateFeesOutGivenBondsIn(uint256 x,uint256,uint256,uint256) internal returns(AaveHyperdrive.HDFee memory) => Bar(x);
    function HDAave.MockCalculateFeesInGivenBondsOut(uint256 x,uint256,uint256,uint256) internal returns(AaveHyperdrive.HDFee memory) => Baz(x);
    /// Hyperdrive Math
    //function _.calculateOpenShort(uint256,uint256,uint256,uint256,uint256,uint256,uint256) internal library => NONDET;
    //function _.calculateCloseShort(uint256,uint256,uint256,uint256,uint256,uint256,uint256) internal library => NONDET;
    //function _.calculateOpenLong(uint256,uint256,uint256,uint256,uint256,uint256,uint256) internal library => NONDET;
    //function _.calculateCloseLong(uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256) internal library => NONDET;
}

function Foo(uint256 x) returns AaveHyperdrive.HDFee {
    AaveHyperdrive.HDFee f;
    require f.totalCurveFee == require_uint256(x/1000);
    return f;
}

function Bar(uint256 x) returns AaveHyperdrive.HDFee {
    AaveHyperdrive.HDFee f;
    require f.totalCurveFee == require_uint256(x/1000);
    return f;
}

function Baz(uint256 x) returns AaveHyperdrive.HDFee {
    AaveHyperdrive.HDFee f;
    require f.totalCurveFee == require_uint256(x/1000);
    return f;
}

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

rule sharePriceChangesForOnlyOneCheckPoint(method f) {
    env e;
    calldataarg args;
    uint256 _checkpointA;
    uint256 _checkpointB;

    AaveHyperdrive.Checkpoint a;

    uint128 sharePriceA1 = checkPointSharePrice(_checkpointA);
    uint128 sharePriceB1 = checkPointSharePrice(_checkpointB);
        f(e, args);
    uint128 sharePriceA2 = checkPointSharePrice(_checkpointA);
    uint128 sharePriceB2 = checkPointSharePrice(_checkpointB);

    assert (sharePriceA1 != sharePriceA2 && sharePriceB1 != sharePriceB2)
        => _checkpointA == _checkpointB;
}

rule cannotChangeCheckPointSharePriceTwice(uint256 _checkpoint, method f) {
    env e;
    calldataarg args;

    //uint128 sharePrice1 = checkPointSharePrice(_checkpoint);
    AaveHyperdrive.Checkpoint CP1 = checkPoints(_checkpoint);
        f(e,args);
    //uint128 sharePrice2 = checkPointSharePrice(_checkpoint);
    AaveHyperdrive.Checkpoint CP2 = checkPoints(_checkpoint);

    //assert sharePrice1 !=0 => sharePrice1 == sharePrice2;
    assert CP1.sharePrice !=0 => CP1.sharePrice == CP2.sharePrice;
}

/// marketState.longsOutstanding = sum of open longs.
/// marketState.shortsOutstanding = sum of open shorts.