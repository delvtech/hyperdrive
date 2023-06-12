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

rule removeLiquidityEmptyBothReserves() {
    env e;
    calldataarg args;
    setHyperdrivePoolParams();
    requireInvariant SpotPriceIsLessThanOne();
        removeLiquidity(e, args);
    assert stateShareReserves() ==0 <=> stateBondReserves() == 0;
}
