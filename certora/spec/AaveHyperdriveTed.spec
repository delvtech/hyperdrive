import "./AaveHyperdrive.spec";
import "./erc20.spec";
import "./MathSummaries.spec";
import "./Sanity.spec";
import "./HyperdriveStorage.spec";
import "./Fees.spec";


use rule sanity;


methods {
    // function _applyCheckpoint(uint256 _checkpointTime, uint256 _sharePrice) internal returns (uint256) => NONDET;
    function calculateCloseLong(uint256, uint256, uint256) external returns (uint256, uint256, uint256, uint256);
}


/// @notice : in progress
rule calculateCloseLongMonotonic(env e) {
    uint256 _bondAmount1;
    uint256 _sharePrice;
    uint256 _maturityTime;
    uint256 _bondAmount2;

    uint256 shareReservesDelta1;
    uint256 shareReservesDelta2;
    uint256 bondReservesDelta1;
    uint256 bondReservesDelta2;
    uint256 shareProceeds1;
    uint256 shareProceeds2;
    uint256 totalGovernanceFee1;
    uint256 totalGovernanceFee2;

    storage initState = lastStorage;
    shareReservesDelta1, bondReservesDelta1, shareProceeds1, totalGovernanceFee1
        = calculateCloseLong(e, _bondAmount1, _sharePrice, _maturityTime);

    shareReservesDelta2, bondReservesDelta2, shareProceeds2, totalGovernanceFee2
        = calculateCloseLong(e, _bondAmount2, _sharePrice, _maturityTime) at initState;

    assert _bondAmount1 >= _bondAmount2 => shareProceeds1 >= shareProceeds2;
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

/// @doc integrity rule for 'openLong'
/// - There must be assets in the pool after opening a position.
/// - cannot receive more bonds than registered reserves.
// verified when NONDET _applyCheckpoint here: https://vaas-stg.certora.com/output/40577/9da7ab069dec4974b252ae247a859648/?anonymousKey=37631daa16d7fa8e3d3a747e828d32e0128bb4b4
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

rule openLongPreservesOutstandingLongs(env e) {
    uint256 baseAmount;
    uint256 minOutput;
    address destination;
    bool asUnderlying;

    require checkpointDuration() != 0;
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

// Verified with NONDET _applyCheckpoint.
rule openLongReallyOpensLong(env e) {
    uint256 baseAmount;
    uint256 minOutput;
    address destination;
    bool asUnderlying;

    setHyperdrivePoolParams();

    uint256 latestCP = require_uint256(e.block.timestamp -
            (e.block.timestamp % checkpointDuration()));

    uint256 anyCheckpoint;
    bool myRequire = checkPointSharePrice(anyCheckpoint) != 0;
    //bool myRequire = _checkpoints[latestCP].sharePrice != 0;
    require(myRequire);

    AaveHyperdrive.MarketState preState = marketState();
    mathint longsOutstanding1 = preState.longsOutstanding;

    uint256 bondsReceived =
        openLong(e, baseAmount, minOutput, destination, asUnderlying);

    require(bondsReceived < 1329227995784915872903807060280344576); // 2^120

    AaveHyperdrive.MarketState postState = marketState();
    mathint longsOutstanding2 = postState.longsOutstanding;

    assert longsOutstanding2 >= longsOutstanding1;
    assert longsOutstanding1 + bondsReceived == longsOutstanding2;
}

// rule calculateTimeRemainingZero(env e) {
//     uint256 _positionDuration;
//     uint256 latestCP = require_uint256(e.block.timestamp -
//             (e.block.timestamp % checkpointDuration()));
//     uint256 maturityTime = require_uint256(latestCP + _positionDuration);
//     uint256 timeRemaining = _calculateTimeRemaining(e, maturityTime);
//     assert maturityTime <= latestCP => timeRemaining == 0;
//     // assert maturityTime > latestCP => timeRemaining = (_maturityTime - latestCP).divDown(_positionDuration) ;
// }

/// @doc Closing a long position at maturity should return the same number of tokens as the number of bonds.
rule closeLongAtMaturity(uint256 bondAmount) {
    env e;
    uint256 minOutput;
    address destination;
    bool asUnderlying;
    uint256 maturityTime;

    require to_mathint(aToken.balanceOf(e, currentContract)) >= to_mathint(totalShares());
    require totalShares() != 0;

    uint256 assetsRecieved =
        closeLong(e, maturityTime, bondAmount, minOutput, destination, asUnderlying);

    assert maturityTime >= e.block.timestamp => assetsRecieved == bondAmount;
}

// rule openLong() {

// }


/// marketState.longsOutstanding = sum of open longs.
/// marketState.shortsOutstanding = sum of open shorts.