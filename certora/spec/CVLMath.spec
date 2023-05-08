/******************************************
----------- CVL Math Library --------------
*******************************************/

// A restriction on the value of w = x * y / z
// The ratio between x (or y) and z is a rational number a/b or b/a.
// Important : do not set a = 0 or b = 0.
// Note: constRatio(x,y,z,a,b,w) <=> constRatio(x,y,z,b,a,w)
definition constRatio(uint256 x, uint256 y, uint256 z,
 uint256 a, uint256 b, uint256 w) 
        returns bool = 
        ( a * x == b * z && w == require_uint256((b * y) / a )) || 
        ( b * x == a * z && w == require_uint256((a * y) / b )) ||
        ( a * y == b * z && w == require_uint256((b * x) / a )) || 
        ( b * y == a * z && w == require_uint256((a * x) / b ));

// A restriction on the value of w = x * y / z
// The division quotient between x (or y) and z is an integer q or 1/q.
// Important : do not set q=0
definition constQuotient(uint256 x, uint256 y, uint256 z,
 uint256 q, uint256 w) 

        returns bool = 
        ( to_mathint(x) == q * z && to_mathint(w) == q * y ) || 
        ( q * x == to_mathint(z) && to_mathint(w) == y / q ) ||
        ( to_mathint(y) == q * z && to_mathint(w) == q * x ) || 
        ( q * y == to_mathint(z) && to_mathint(w) == x / q );

definition ONE18() returns uint256 = 1000000000000000000;

definition _monotonicallyIncreasing(uint256 x, uint256 y, uint256 fx, uint256 fy) returns bool = 
    (x > y => fx >= fy);

definition _monotonicallyDecreasing(uint256 x, uint256 y, uint256 fx, uint256 fy) returns bool = 
    (x > y => fx <= fy);
        
ghost uint256 res;
ghost mathint rem;
ghost mathint SQRT;

function mulDivDownAbstract(uint256 x, uint256 y, uint256 z) returns uint256 {
    require z !=0;
    uint256 xy = require_uint256(x * y);
    havoc res;
    havoc rem; 
    require z * res + rem == x * y;
    require rem < to_mathint(z);
    return res; 
}

function mulDivDownAbstractPlus(uint256 x, uint256 y, uint256 z) returns uint256 {
    havoc res;
    require z != 0;
    uint256 xy = require_uint256(x*y);

    require res * z <= x * y;
    require res * z + to_mathint(z) > x * y;
    return res; 
}

function mulDivUpAbstractPlus(uint256 x, uint256 y, uint256 z) returns uint256 {
    havoc res;
    require z != 0;
    uint256 xy = require_uint256(x * y);
    uint256 fz = require_uint256(res * z);
    require xy >= fz;
    require res * z + to_mathint(z) > to_mathint(xy);
    
    if(xy == fz) {
        return res;
    } 
    return require_uint256(res + 1);
}

function discreteQuotientMulDiv(uint256 x, uint256 y, uint256 z) returns uint256 
{
    havoc res;
    require z != 0 && noOverFlowMul(x, y);
    // Discrete quotients:
    require( 
        ((x ==0 || y ==0) && res == 0) ||
        (x == z && res == y) || 
        (y == z && res == x) ||
        constQuotient(x, y, z, 2, res) || // Division quotient is 1/2 or 2
        constQuotient(x, y, z, 5, res) || // Division quotient is 1/5 or 5
        constQuotient(x, y, z, 100, res) // Division quotient is 1/100 or 100
        );
    return res;
}

function discreteRatioMulDiv(uint256 x, uint256 y, uint256 z) returns uint256 
{
    havoc res;
    require z != 0 && noOverFlowMul(x, y);
    // Discrete ratios:
    require( 
        ((x ==0 || y ==0) && res == 0) ||
        (x == z && res == y) ||
        (y == z && res == x) ||
        constRatio(x, y, z, 2, 1, res) || // f = 2*x or f = x/2 (same for y)
        constRatio(x, y, z, 5, 1, res) || // f = 5*x or f = x/5 (same for y)
        constRatio(x, y, z, 2, 3, res) || // f = 2*x/3 or f = 3*x/2 (same for y)
        constRatio(x, y, z, 2, 7, res)    // f = 2*x/7 or f = 7*x/2 (same for y)
        );
    return res;
}

function noOverFlowMul(uint256 x, uint256 y) returns bool
{
    return x * y <= max_uint;
}

ghost _ghostPow(uint256, uint256) returns uint256 {
    /// x^1 = x
    axiom forall uint256 x. _ghostPow(x, ONE18()) == x;
    /// 1^y = 1
    axiom forall uint256 y. _ghostPow(ONE18(), y) == ONE18();
    /// I. x > 1 && y1 > y2 => x^y1 < x^y2
    /// II. x < 1 && y1 > y2 => x^y1 > x^y2
    axiom forall uint256 x. forall uint256 y1. forall uint256 y2.
        x >= ONE18() && y1 > y2 => _ghostPow(x, y1) >= _ghostPow(x, y2);
    axiom forall uint256 x. forall uint256 y1. forall uint256 y2.
        x < ONE18() && y1 > y2 => _ghostPow(x, y1) <= _ghostPow(x, y2);
    /// x1 > x2 && y > 0 => x1^y > x2^y
    axiom forall uint256 x1. forall uint256 x2. forall uint256 y.
        x1 > x2 => _ghostPow(x1, y) >= _ghostPow(x2, y);
    /// x^y * x^(1-y) == x
    axiom forall uint256 x. forall uint256 y. forall uint256 z. 
        (0 <= y && y <= ONE18() &&  z + y == to_mathint(ONE18())) => (
        _ghostPow(x, y) * _ghostPow(x, z) == x * ONE18());
}

function CVLPow(uint256 x, uint256 y) returns uint256 {
    if (y == 0) {return ONE18();}
    if (x == 0) {return 0;}
    return _ghostPow(x, y);
}

function CVLSqrt(uint256 x) returns uint256 {
    havoc SQRT;
    require SQRT*SQRT <= to_mathint(x) && (SQRT + 1)*(SQRT + 1) > to_mathint(x);
    return require_uint256(SQRT);
}
