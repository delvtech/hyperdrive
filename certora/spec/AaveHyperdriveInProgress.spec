import "./AaveHyperdriveVerified.spec";

use invariant SumOfLongsGEOutstanding;
use invariant SumOfShortsGEOutstanding;
use invariant WithdrawalSharesGEReadyShares;


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
        uint256 sharesMinted = mulDivDownAbstractPlus(totalSharesBefore, baseAmount, assetsBefore);
        //uint256 sharePrice = mulDivDownAbstractPlus(baseAmount, ONE18(), sharesMinted);
        assert totalSharesBefore + sharesMinted == to_mathint(totalSharesAfter);
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


// STATUS - in progress
// timeout after adding `require maturityTime1 < eCl.block.timestamp && maturityTime2 < eCl.block.timestamp;`
// https://prover.certora.com/output/3106/2e6dc3d3b5c146bcb5ceb865fb1320c7/?anonymousKey=6e9c436ed99051ae53b036977260fe3247911c9e
rule profitIsMonotonicForCloseLong(env eCl) {
    uint256 bondAmount;
    uint256 minOutput;
    address destination1; address destination2;
    uint256 maturityTime1; uint256 maturityTime2;
    bool asUnderlying1; bool asUnderlying2;

    require maturityTime1 > eCl.block.timestamp && maturityTime2 > eCl.block.timestamp;

    storage initState = lastStorage;
    uint256 assetsRecieved1 =
        closeLong(eCl, maturityTime1, bondAmount, minOutput, destination1, asUnderlying1);

    uint256 assetsRecieved2 =
        closeLong(eCl, maturityTime2, bondAmount, minOutput, destination2, asUnderlying2) at initState;

    assert maturityTime1 >= maturityTime2 => assetsRecieved1 <= assetsRecieved2, "Received assets should increase for long position.";
}


// STATUS - violation
// https://prover.certora.com/output/3106/90f5e72f826643e184aa49baacca100c/?anonymousKey=22f84ff36a5192c746e75b57607a415d50dcd420
rule addAndRemoveSameSharesMeansNoChange(env e) {
    uint256 _contribution;
    uint256 _minApr;
    uint256 _maxApr;
    address _destination;
    bool _asUnderlying;

    uint256 _minOutput;
    uint256 baseProceeds;
    uint256 withdrawalShares;

    uint128 shareReservesBefore = stateShareReserves();
        uint256 lpShares = addLiquidity(e, _contribution, _minApr, _maxApr, _destination, _asUnderlying);
        baseProceeds, withdrawalShares = removeLiquidity(e, lpShares, _minOutput, _destination, _asUnderlying);
    uint128 shareReservesAfter = stateShareReserves();

    assert shareReservesAfter + 1 >= to_mathint(shareReservesBefore);
}


rule openLongPreservesOutstandingLongs(uint256 baseAmount) {
    env e;
    uint256 minOutput;
    address destination;
    bool asUnderlying;

    setHyperdrivePoolParams();
    requireInvariant aTokenBalanceGEToShares(e);
    requireInvariant SumOfShortsGEOutstanding();
    requireInvariant SumOfLongsGEOutstanding();

    uint256 latestCP = require_uint256(e.block.timestamp -
            (e.block.timestamp % checkpointDuration()));

    IHyperdrive.MarketState preState = marketState();
    uint128 bondReserves1 = preState.bondReserves;
    uint128 longsOutstanding1 = preState.longsOutstanding;
    uint256 sharePrice1 = sharePrice(e);
    require to_mathint(checkPointSharePrice(latestCP)) == to_mathint(sharePrice1);

    require mulUpWad(sharePrice1, bondReserves1) >= assert_uint256(longsOutstanding1);

    uint256 maturityTime; uint256 bondProceeds;
    maturityTime, bondProceeds = 
        openLong(e, baseAmount, minOutput, destination, asUnderlying);

    IHyperdrive.MarketState postState = marketState();
    uint128 bondReserves2 = postState.bondReserves;
    uint128 longsOutstanding2 = postState.longsOutstanding;
    uint256 sharePrice2 = sharePrice(e);

    assert mulUpWad(sharePrice2, bondReserves2) >= assert_uint256(longsOutstanding2);
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


/// The Spot price p = [(mu * z / y) ^ tau] must be smaller than one.
/// Violated
/// https://vaas-stg.certora.com/output/41958/794fadd9600c4a728e23eca6712b6b66/?anonymousKey=a3bc9d0843c440ba8c78610f331c921eb65744e9
invariant SpotPriceIsLessThanOne()
    stateBondReserves() != 0 => mulDivDownAbstractPlus(stateShareReserves(), initialSharePrice(), stateBondReserves()) <= ONE18()
    filtered{f -> isOpenShort(f)}
    {
        preserved with (env e) {
            setHyperdrivePoolParams();
            require sharePrice(e) >= initialSharePrice(); 
        }
    }


/// @notice The average maturity time should always be between the current time stamp and the time stamp + duration.
/// In other words, matured positions should not be taken into account in the average time.
invariant LongAverageMaturityTimeIsBounded(env e)
    (stateLongs() == 0 => AvgMTimeLongs() == 0) &&
    (stateLongs() != 0 => 
        AvgMTimeLongs() >= e.block.timestamp * ONE18() &&
        AvgMTimeLongs() <= ONE18()*(e.block.timestamp + positionDuration()))
    filtered {f -> isOpenLong(f)}
    {
        preserved with (env eP) {
            require e.block.timestamp == eP.block.timestamp;
            setHyperdrivePoolParams();
            requireInvariant SumOfLongsGEOutstanding();
            // require stateLongs() == 0;
        }
    }


/// @notice The average maturity time should always be between the current time stamp and the time stamp + duration.
/// In other words, matured positions should not be taken into account in the average time.
invariant ShortAverageMaturityTimeIsBounded(env e)
    (stateShorts() == 0 => AvgMTimeShorts() == 0) &&
    (stateShorts() != 0 => 
        AvgMTimeShorts() >= e.block.timestamp * ONE18() &&
        AvgMTimeShorts() <= ONE18()*(e.block.timestamp + positionDuration()))
    filtered {f -> isOpenLong(f)}
    {
        preserved with (env eP) {
            require e.block.timestamp == eP.block.timestamp;
            setHyperdrivePoolParams();
            requireInvariant SumOfShortsGEOutstanding();
        }
    }


rule SharePriceCannotDecreaseAfterOperation(method f)
    filtered{f -> isCloseLong(f)} {
    env e;
    calldataarg args;
    uint256 sharePriceBefore = sharePrice(e);
    // require sharePriceBefore >= 2 * 10^18; // To get better counterexample
        f(e, args);
    uint256 sharePriceAfter = sharePrice(e);

    require aToken.balanceOf(e, currentContract) != 0; // non-zero shares
    require totalShares() != 0; // non-zero assets
    assert sharePriceAfter >= sharePriceBefore;
    // assert 5 * sharePriceAfter >= 3 * sharePriceBefore;
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


invariant TotalSharesGreaterThanLiquidity()
    to_mathint(stateShareReserves()) <= to_mathint(totalShares())
    filtered{f -> isCloseShort(f)}


invariant TotalSharesGreaterThanLongs(env e)
    to_mathint(stateLongs()) <= to_mathint(totalShares()) * sharePrice(e)
    filtered{f -> isCloseShort(f)}


/// If there are no shares in the pool, then there are only shorts in the pool (no longs)
/// Probably Unreal Violation:
/// https://prover.certora.com/output/40577/c002ed40599e448a8391975ff4ba94db/?anonymousKey=0b24b9373c24264c61a22188b6863615e903e13f
/// When closeShort called, it induced 
/// pricePerShare  ........ 10^18 + 5 -> ?
/// shareReserves ......... 10^18     -> 0                    // in function _updateLiquidity called from HyperdriveLong._applyCloseLong which was called from applyCheckpoint
/// stateLongs  ........... MAXUINT   -> MAXUINT - (10^18+4)
invariant NoSharesNoLongs(env e)
    stateShareReserves() == 0 => stateLongs() == 0
    filtered{f -> !isRemoveLiq(f)}
    {
        preserved with (env eP)  {
            require e.block.timestamp == eP.block.timestamp;
            setHyperdrivePoolParams();
            requireInvariant SumOfLongsGEOutstanding();
            requireInvariant SumOfShortsGEOutstanding();
            requireInvariant TotalSharesGreaterThanLiquidity();
            requireInvariant TotalSharesGreaterThanLongs(eP);
            requireInvariant ShareReservesCoverLongs(eP);
            // There always should be more money than bonds(=longs)
            // require stateLongs() == 0;
            // require stateLongs() < 10 * RAY();
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
    
    uint256 maturityTime;
    uint256 userDeposit;

    IHyperdrive.MarketState Mstate = marketState();
    uint128 baseVolumeBefore = Mstate.shortBaseVolume;
        maturityTime, userDeposit = openShort(e, bondAmount, maxDeposit, destination, asUnderlying);
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
// no summarization: https://prover.certora.com/output/3106/5556eaa47094442183fed567a81aa14b/?anonymousKey=3e7c111ec98a0150c917b774ff85bcca9ec5deb7
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
    uint256 traderDeposit;
    _, traderDeposit = openShort(e1, bondAmount, maxDeposit, destination, false);
    uint256 balance2 = aToken.balanceOf(e1, e1.msg.sender);

    assert traderDeposit != 0;
}


/// Violated:
/// https://vaas-stg.certora.com/output/41958/180ad13e3b71470dbb54453056e5b4f7/?anonymousKey=462752cde7c7ecca90733908249a351c0425f2f7
rule addLiquidityPreservesAPR() {
    env e;
    calldataarg args;
    setHyperdrivePoolParams();
    
    uint256 mu = initialSharePrice();
    uint256 z1 = stateShareReserves(); require z1 >= ONE18();
    uint256 y1 = stateBondReserves(); require y1 !=0;
    uint256 R1 = mulDivDownAbstractPlus(z1, mu, y1);
    require R1 <= ONE18(); // The fixed interest should be > 1
        addLiquidity(e, args);
    uint256 z2 = stateShareReserves();
    uint256 y2 = stateBondReserves();
    uint256 R2 = mulDivDownAbstractPlus(z2, mu, y2);

    assert z2 != 0 && y2 != 0, "Sanity check";
    assert abs(R1-R2) < 2, "APR was changed beyond allowed error bound";
}


/// Violated
rule removeLiquidityPreservesAPR() {
    env e;
    calldataarg args;
    setHyperdrivePoolParams();

    uint256 mu = initialSharePrice();
    uint256 z1 = stateShareReserves(); require z1 >= ONE18();
    uint256 y1 = stateBondReserves(); require y1 !=0;
    uint256 R1 = mulDivDownAbstractPlus(z1, mu, y1);
    require R1 <= ONE18(); // The fixed interest should be > 1
        removeLiquidity(e, args);
    uint256 z2 = stateShareReserves();
    uint256 y2 = stateBondReserves();
    uint256 R2 = mulDivDownAbstractPlus(z2, mu, y2);

    // Assuming the pool isn't depleted
    require (z2 != 0 && y2 != 0);
    assert abs(R1-R2) < 2, "APR was changed beyond allowed error bound";
}


/// The change of the the share reserves should account for three sources:
///     a. Deposit or withdrawal of pool shares from adding/removing liquidity
///     b. Closing matured shorts and longs (by checkpointing)
///     c. Transfer of shares to the ready-to-redeem withdrawal pool
rule changeOfShareReserves() {
    env e;
    calldataarg args;
    uint256 price = sharePrice(e); require price !=0 ;
    setHyperdrivePoolParams();
    requireInvariant TotalSharesGreaterThanLiquidity();
    
    uint256 totalShares1 = totalShares();
    uint128 shareReserves1 = stateShareReserves();
    mathint readyProceeds1 = withdrawalProceeds();
    mathint Longs1 = stateLongs();
    mathint Shorts1 = stateShorts();
        addLiquidity(e, args); // also remove
    uint256 totalShares2 = totalShares();
    uint128 shareReserves2 = stateShareReserves();
    mathint readyProceeds2 = withdrawalProceeds();
    mathint Longs2 = stateLongs();
    mathint Shorts2 = stateShorts();
    
    mathint longProceeds = ((Longs2 - Longs1) * ONE18()) / price;
    mathint shortProceeds = ((Shorts2 - Shorts1) * ONE18()) / price;

    require shareReserves1 > 0;
    ///
    assert shareReserves2 - shareReserves1 == 
        (shortProceeds - longProceeds) + 
        (totalShares2 - totalShares1) -
        (readyProceeds2 - readyProceeds1);
}


rule removeLiquidityEmptyBothReserves() {
    env e;
    calldataarg args;
    setHyperdrivePoolParams();
    requireInvariant SpotPriceIsLessThanOne();
        removeLiquidity(e, args);
    assert stateShareReserves() == 0 <=> stateBondReserves() == 0;
}
