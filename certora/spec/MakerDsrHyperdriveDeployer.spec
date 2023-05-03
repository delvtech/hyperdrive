methods {
}

rule sanity(env e, method f) {
    calldataarg args;
    f(e, args);
    assert false;
}
