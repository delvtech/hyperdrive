import "./AaveHyperdrive.spec";
use invariant SpotPriceIsLessThanOne;

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

    assert z2 !=0 && y2 !=0, "Sanity check";
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
    require (z2 !=0 && y2 !=0);
    assert abs(R1-R2) < 2, "APR was changed beyond allowed error bound";
}


/// The change of the the share reserves should account for three sources:
///     a. Deposit of withdrawal of pool shares from adding/removing liquidity
///     b. Closing matured shorts and longs (by checkpointing)
///     c. Transfer of shares to the ready-to-redeem withdrawal pool
rule changeOfShareReserves() {
    env e;
    calldataarg args;
    uint256 price = sharePrice(e); require price !=0 ;
    setHyperdrivePoolParams();
    
    uint256 totalShares1 = totalShares();
    uint128 shareReserves1 = stateShareReserves();
    mathint readyProceeds1 = withdrawalProceeds();
    mathint sumOfLongs1 = sumOfLongs();
    mathint sumOfShorts1 = sumOfShorts();
        addLiquidity(e, args); // also remove
    uint256 totalShares2 = totalShares();
    uint128 shareReserves2 = stateShareReserves();
    mathint readyProceeds2 = withdrawalProceeds();
    mathint sumOfLongs2 = sumOfLongs();
    mathint sumOfShorts2 = sumOfShorts();
    
    mathint longProceeds = ((sumOfLongs2 - sumOfLongs1) * ONE18()) / price;
    mathint shortProceeds = ((sumOfShorts2 - sumOfShorts1) * ONE18()) / price;

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
    assert stateShareReserves() ==0 <=> stateBondReserves() == 0;
}
