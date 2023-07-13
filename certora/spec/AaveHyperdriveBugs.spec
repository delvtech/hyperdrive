import "./AaveHyperdriveInProgress.spec";

using MockFixedPointMath as FPMath;

use invariant SumOfLongsGEOutstanding;
use invariant SumOfShortsGEOutstanding;
use invariant WithdrawalSharesGEReadyShares;
use invariant SpotPriceIsLessThanOne;

methods {
    function FPMath.updateWeightedAverage(uint256,uint256,uint256,uint256,bool) external returns (uint256) envfree;
}

// Counter example when trader had opened long position covering all money in the pool:
// When trader comes and closes the position, he returns all the bonds he has and get all the shares
// present in the pool. Resulting in zero shares in the pool, meaning, that _pricePerShare = 0, meaning sharePrice() == 0 
// https://prover.certora.com/output/40577/3c3ca3c5cf954d91919a1f8854c35265/?anonymousKey=fd43525a0a4bb704c529e645938885bb049fe59e
// Even more interesting violation is one capturing when _pricePerShare went from 1 to 8/9 when closing a big long:
// https://prover.certora.com/output/40577/476f67e7466140ed9201b9feae0f72c3/?anonymousKey=ed105fa247c69313ebcc2c35d543135c88533ae0
/// @notice The share price cannot go below the initial price.
invariant SharePriceAlwaysGreaterThanInitial(env e)
    sharePrice(e) >= initialSharePrice()
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


/// Violated
/// @notice checkpoint() function correctly sets _checkpoints[time].sharePrice
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


rule updateWeightedAverageCheck(uint256 avg, uint256 totW, uint256 del, uint256 delW) {
    bool isAdd;
    uint256 avg_new = FPMath.updateWeightedAverage(avg,totW,del,delW,isAdd);
    mathint DeltAvg = avg_new - avg;
    if(isAdd) {
        assert weightedAverage(del-avg,delW,totW,DeltAvg);
    }
    else {
        assert weightedAverage(del-avg,0-delW,totW,DeltAvg);
    }
}
