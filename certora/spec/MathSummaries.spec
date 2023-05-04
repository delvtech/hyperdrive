import "./CVLMath.spec";

methods {
    function _.pow(uint256 x, uint256 y) internal library => CVLPow(x, y) expect uint256;
    function _.exp(int256) internal library => NONDET;
    function _.ln(int256) internal library => NONDET;
    function _.updateWeightedAverage(uint256,uint256,uint256,uint256,bool) internal library  => NONDET;
    function _.mulDivDown(uint256 x, uint256 y, uint256 d) internal library => mulDivDownAbstractPlus(x, y, d) expect uint256;
    function _.mulDivUp(uint256 x, uint256 y, uint256 d) internal library => mulDivUpAbstractPlus(x, y, d) expect uint256;
}