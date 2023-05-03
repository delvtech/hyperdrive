import "erc20.spec";

methods {
    function _.mulDivDown(uint256 x, uint256 y, uint256 d) internal library => mulDivDownCVL(x, y, d) expect uint256;
    function _.mulDivUp(uint256 x, uint256 y, uint256 d) internal library => mulDivUpCVL(x, y, d) expect uint256;

    function _.pieOf(address) external => NONDET;
    function _.chi() external => NONDET;
    function _.rho() external => NONDET;
    function _.dsr() external => NONDET;
}

function mulDivDownCVL(uint256 x, uint256 y, uint256 z) returns uint256 {
    require z!=0;
    return require_uint256( x * y / z);
}

function mulDivUpCVL(uint256 x, uint256 y, uint256 z) returns uint256 {
    require z!=0;
    uint256 w =  require_uint256( x * y / z);
    if(w*z == x*y) {
        return w;
    }
    return require_uint256(w+1);
}

rule sanity(env e, method f) {
    calldataarg args;
    f(e, args);
    assert false;
}
