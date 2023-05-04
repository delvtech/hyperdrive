import "erc20.spec";

methods {
    // Hyperdrive
    function _.initialize(uint256, uint256, address, bool) external => DISPATCHER(true);
}

rule sanity(env e, method f) {
    calldataarg args;
    f(e, args);
    assert false;
}
