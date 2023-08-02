import "./AaveHyperdriveSetup.spec";

methods {
    function Hyperdrive._applyCheckpoint(uint256 _checkpointTime, uint256 _sharePrice) internal returns (uint256) => NONDET;
}

/// When calling openLong a long position is opened 
/// Verified with NONDET _applyCheckpoint.
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

    IHyperdrive.MarketState preState = marketState();
    mathint longsOutstanding1 = preState.longsOutstanding;

    uint256 maturityTime; uint256 bondProceeds;
    maturityTime, bondProceeds = 
        openLong(e, baseAmount, minOutput, destination, asUnderlying);

    require(bondsReceived < 1329227995784915872903807060280344576); // 2^120

    IHyperdrive.MarketState postState = marketState();
    mathint longsOutstanding2 = postState.longsOutstanding;

    assert longsOutstanding2 >= longsOutstanding1;
    assert longsOutstanding1 + bondProceeds == longsOutstanding2;
}
