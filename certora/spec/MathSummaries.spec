import "./CVLMath.spec";

methods {
    /// FixedPoint Math
    /// @dev Updates a weighted average by adding or removing a weighted delta.
    function _.updateWeightedAverage(uint256, uint256, uint256, uint256 ,bool) 
        internal library => NONDET;// ghostUpdateWeightedAverage(avg, totW, del, delW, isAdd) expect uint256;
    function _.pow(uint256 x, uint256 y) internal library => CVLPow(x, y) expect uint256;
    function _.exp(int256) internal library => NONDET;
    function _.ln(int256) internal library => NONDET;
    function _.mulDivDown(uint256 x, uint256 y, uint256 d) internal library => mulDivDownAbstractPlus(x, y, d) expect uint256;
    function _.mulDivUp(uint256 x, uint256 y, uint256 d) internal library => mulDivUpAbstractPlus(x, y, d) expect uint256;

    /// YieldSpace Math
    /// @dev Calculates the amount of bonds a user must provide the pool to receive
    /// a specified amount of shares
    function _.calculateBondsInGivenSharesOut(uint256 z,uint256 y, uint256 dz,uint256 t,uint256 c, uint256 mu)
        internal library => ghostBondsInGivenSharesOut(z,y,dz,t,c,mu) expect uint256;
    /// @dev Calculates the amount of bonds a user will receive from the pool by
    /// providing a specified amount of shares
    function _.calculateBondsOutGivenSharesIn(uint256 z,uint256 y, uint256 dz,uint256 t,uint256 c, uint256 mu)
        internal library => ghostBondsOutGivenSharesIn(z,y,dz,t,c,mu) expect uint256;
    /// @dev Calculates the amount of shares a user must provide the pool to receive
    /// a specified amount of bonds
    function _.calculateSharesInGivenBondsOut(uint256 z,uint256 y, uint256 dz,uint256 t,uint256 c, uint256 mu)
        internal library => ghostSharesInGivenBondsOut(z,y,dz,t,c,mu) expect uint256; 
    /// @dev Calculates the amount of shares a user will receive from the pool by
    /// providing a specified amount of bonds
    function _.calculateSharesOutGivenBondsIn(uint256 z,uint256 y, uint256 dz,uint256 t,uint256 c, uint256 mu)
        internal library => ghostSharesOutGivenBondsIn(z,y,dz,t,c,mu) expect uint256;
}

/// Ghost implementations of FixedPoint Math
ghost ghostUpdateWeightedAverage(uint256,uint256,uint256,uint256,bool) returns uint256;

/// Ghost implementations of YieldSpace Math
ghost ghostBondsInGivenSharesOut(uint256,uint256,uint256,uint256,uint256,uint256) returns uint256;
ghost ghostBondsOutGivenSharesIn(uint256,uint256,uint256,uint256,uint256,uint256) returns uint256;
ghost ghostSharesInGivenBondsOut(uint256,uint256,uint256,uint256,uint256,uint256) returns uint256;
ghost ghostSharesOutGivenBondsIn(uint256,uint256,uint256,uint256,uint256,uint256) returns uint256;
