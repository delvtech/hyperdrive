methods {
    function _._ilog2(uint256 x) private pure returns (uint256 r)
}

rule sanity(env e, method f) {
    calldataarg args;
    f(e, args);
    assert false;
}
