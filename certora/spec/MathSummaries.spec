import "./CVLMath.spec";

methods {
    /// FixedPoint Math
    /// @dev Updates a weighted average by adding or removing a weighted delta.
    function _.updateWeightedAverage(uint256,uint256,uint256,uint256,bool) internal library => NONDET;
    //function _.updateWeightedAverage(uint256 avg, uint256 totW, uint256 del, uint256 delW ,bool isAdd) 
    //    internal library => ghostUpdateWeightedAverage(avg, totW, del, delW, isAdd) expect uint256;
    function _.pow(uint256 x, uint256 y) internal library => CVLPow(x, y) expect uint256;
    function _.exp(int256) internal library => NONDET;
    function _.ln(int256) internal library => NONDET;
    function _.mulDivDown(uint256 x, uint256 y, uint256 d) internal library => mulDivDownAbstractPlus(x, y, d) expect uint256;
    function _.mulDivUp(uint256 x, uint256 y, uint256 d) internal library => mulDivUpAbstractPlus(x, y, d) expect uint256;

    /// YieldSpace (YS) Math
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

    /// Hyperdrive (HD) Math
    /// @dev Calculates the base volume of an open trade given the base amount, the bond amount, and the time remaining.
    function _.calculateBaseVolume(uint256 base, uint256 bond ,uint256 time) internal library 
        => ghostCalculateBaseVolume(base, bond, time) expect uint256;
    
    /// @dev Calculates the spot price without slippage of bonds in terms of shares.
    function _.calculateSpotPrice(uint256 shares, uint256 bonds, uint256 initPrice, uint256 normTime, uint256 timeSt) internal library 
        => ghostCalculateSpotPrice(shares, bonds, initPrice, normTime, timeSt) expect uint256;
    
    /// @dev Calculates the APR from the pool's reserves.
    function _.calculateAPRFromReserves(uint256 shares, uint256 bonds, uint256 initPrice, uint256 dur, uint256 timeSt) internal library
        => ghostCalculateAPRFromReserves(shares, bonds, initPrice, dur, timeSt) expect uint256;
    
    /// @dev Calculates the initial bond reserves assuming that the initial LP
    function _.calculateInitialBondReserves(uint256 shares, uint256 price, uint256 initPrice, uint256 APR, uint256 dur, uint256 timeSt) internal library 
        => ghostCalculateInitialBondReserves(shares, price, initPrice, APR, dur, timeSt) expect uint256;
    
    /// @dev Calculates the present value LPs capital in the pool.
    function _.calculatePresentValue(HyperdriveMath.PresentValueParams memory) internal library => NONDET; 
    
    /// @dev Calculates the interest in shares earned by a short position
    function _.calculateShortInterest(uint256 bond, uint256 openPrice, uint256 closePrice, uint256 price) internal library 
        => ghostCalculateShortInterest(bond, openPrice, closePrice, price) expect uint256;
    
    /// @dev Calculates the proceeds in shares of closing a short position.
    function _.calculateShortProceeds(uint256 bond, uint256 share, uint256 openPrice, uint256 closePrice, uint256 price) internal library 
        => ghostCalculateShortProceeds(bond, share, openPrice, closePrice, price) expect uint256;
}

/// Ghost implementations of FixedPoint Math
ghost ghostUpdateWeightedAverage(uint256,uint256,uint256,uint256,bool) returns uint256;

/// Ghost implementations of YieldSpace Math
ghost ghostBondsInGivenSharesOut(uint256,uint256,uint256,uint256,uint256,uint256) returns uint256;
ghost ghostBondsOutGivenSharesIn(uint256,uint256,uint256,uint256,uint256,uint256) returns uint256;
ghost ghostSharesInGivenBondsOut(uint256,uint256,uint256,uint256,uint256,uint256) returns uint256;
ghost ghostSharesOutGivenBondsIn(uint256,uint256,uint256,uint256,uint256,uint256) returns uint256;

/// Ghost implementations of Hyperdrive Math
ghost ghostCalculateBaseVolume(uint256,uint256,uint256) returns uint256 {
    axiom forall uint256 x. forall uint256 y. 
        forall uint256 z. forall uint256 w. 
            _monotonicallyIncreasing(x, y , ghostCalculateBaseVolume(x,z,w), ghostCalculateBaseVolume(y,z,w));
}

ghost ghostCalculateSpotPrice(uint256,uint256,uint256,uint256,uint256) returns uint256;
ghost ghostCalculateAPRFromReserves(uint256,uint256,uint256,uint256,uint256) returns uint256;
ghost ghostCalculateInitialBondReserves(uint256,uint256,uint256,uint256,uint256,uint256) returns uint256;
ghost ghostCalculateShortInterest(uint256,uint256,uint256,uint256) returns uint256;
ghost ghostCalculateShortProceeds(uint256,uint256,uint256,uint256,uint256) returns uint256;