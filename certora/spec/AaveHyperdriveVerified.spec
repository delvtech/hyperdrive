import "./AaveHyperdriveSetup.spec";

/// Checks the balance difference after transfering aTokens.
/// Due to rounding errors of index divison and multiplication, the difference
/// is bounded by index + 1/RAY
/// @notice [VERIFIED]
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


/// No action can change the share price for two different checkpoints at the same time.
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

    IHyperdrive.Checkpoint CP1 = checkPoints(_checkpoint);
        f(e,args);
    IHyperdrive.Checkpoint CP2 = checkPoints(_checkpoint);

    assert CP1.sharePrice !=0 => CP1.sharePrice == CP2.sharePrice;
}


/// No function can change the total supply of two different tokens at the same time.
/// @notice the only exception to this rule is 
/// the function removeLiqudity() that can change both LP tokens types only!
/// @notice [VERIFIED]
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


/// Verified
invariant NoFutureTokens(uint256 AssetId, env e)
    timeByID(AssetId) > e.block.timestamp + positionDuration() => totalSupplyByToken(AssetId) == 0
    {
        preserved with (env eP) {
            require e.block.timestamp == eP.block.timestamp;
        }
    }


/// The ready to redeem shares cannot exceed the total withdrawal shares.
/// [VERIFIED]
invariant WithdrawalSharesGEReadyShares()
    totalWithdrawalShares() >= readyToRedeemShares();


/// The sum of longs tokens is greater or equal to the outstanding longs.
/// @notice The sum is not necessarily equal to the outstanding count.
/// @notice [VERIFIED]
invariant SumOfLongsGEOutstanding()
    sumOfLongs() >= to_mathint(stateLongs())
    {
        preserved closeLong(uint256 _maturityTime, uint256 _bondAmount, uint256 _minOutput, address _destination, bool _asUnderlying) with (env e2) {
            require checkPointSharePrice(_maturityTime) != 0 => (sumOfLongs() >= stateLongs() + _bondAmount);
        }
    }


/// The sum of shorts tokens is greater or equal to the outstanding shorts.
/// @notice The sum is not necessarily equal to the outstanding count.
/// @notice [VERIFIED]
invariant SumOfShortsGEOutstanding()
    sumOfShorts() >= to_mathint(stateShorts())
    {
        preserved closeShort(uint256 _maturityTime, uint256 _bondAmount, uint256 _minOutput, address _destination, bool _asUnderlying) with (env e2) {
            require checkPointSharePrice(_maturityTime) != 0 => (sumOfShorts() >= stateShorts() + _bondAmount);
        }
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

    uint256 bondsReceived =
        openLong(e, baseAmount, minOutput, destination, asUnderlying);

    require(bondsReceived < 1329227995784915872903807060280344576); // 2^120

    IHyperdrive.MarketState postState = marketState();
    mathint longsOutstanding2 = postState.longsOutstanding;

    assert longsOutstanding2 >= longsOutstanding1;
    assert longsOutstanding1 + bondsReceived == longsOutstanding2;
}


// STATUS - verified
// trader won't spend more baseTokens/aTokens than maxDeposit when open short.
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
