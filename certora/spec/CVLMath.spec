
// A restriction on the value of f = x * y / z
// The ratio between x (or y) and z is a rational number a/b or b/a.
// Important : do not set a = 0 or b = 0.
// Note: constRatio(x,y,z,a,b,f) <=> constRatio(x,y,z,b,a,f)
definition constRatio(uint256 x, uint256 y, uint256 z,
 uint256 a, uint256 b, uint256 f) 
        returns bool = 
        ( a * x == b * z && f == require_uint256((b * y) / a )) || 
        ( b * x == a * z && f == require_uint256((a * y) / b )) ||
        ( a * y == b * z && f == require_uint256((b * x) / a )) || 
        ( b * y == a * z && f == require_uint256((a * x) / b ));

// A restriction on the value of f = x * y / z
// The division quotient between x (or y) and z is an integer q or 1/q.
// Important : do not set q=0
definition constQuotient(uint256 x, uint256 y, uint256 z,
 uint256 q, uint256 f) 

        returns bool = 
        ( to_mathint(x) == q * z && to_mathint(f) == q * y ) || 
        ( q * x == to_mathint(z) && to_mathint(f) == y / q ) ||
        ( to_mathint(y) == q * z && to_mathint(f) == q * x ) || 
        ( q * y == to_mathint(z) && to_mathint(f) == x / q );

definition ONE18() returns uint256 = 1000000000000000000;

function mulDivDownAbstract(uint256 x, uint256 y, uint256 z) returns uint256 {
    require z !=0;
    uint256 xy = require_uint256(x * y);
    uint256 f;
    uint256 r; 
    require z * f + to_mathint(r) == x * y;
    require r < z;
    return f; 
}

function mulDivDownAbstractPlus(uint256 x, uint256 y, uint256 z) returns uint256 {
    uint256 f;
    require z != 0;
    uint256 xy = assert_uint256(x*y);

    require f * z <= x * y;
    require f * z + to_mathint(z) > x * y;
    return f; 
}

function mulDivUpAbstractPlus(uint256 x, uint256 y, uint256 z) returns uint256 {
    uint256 f;
    require z != 0;
    uint256 xy = assert_uint256(x*y);

    mathint r = x * y - f * z;
    require r >= 0;
    require f * z + to_mathint(z) > x * y;
    if(r == 0) {
        return f;
    } 
    return assert_uint256(f + 1);
}

function discreteQuotientMulDiv(uint256 x, uint256 y, uint256 z) returns uint256 
{
    uint256 f;
    require z != 0 && noOverFlowMul(x, y);
    // Discrete quotients:
    require( 
        ((x ==0 || y ==0) && f == 0) ||
        (x == z && f == y) || 
        (y == z && f == x) ||
        constQuotient(x, y, z, 2, f) || // Division quotient is 1/2 or 2
        constQuotient(x, y, z, 5, f) || // Division quotient is 1/5 or 5
        constQuotient(x, y, z, 100, f) // Division quotient is 1/100 or 100
        );
    return f;
}

function discreteRatioMulDiv(uint256 x, uint256 y, uint256 z) returns uint256 
{
    uint256 f;
    require z != 0 && noOverFlowMul(x, y);
    // Discrete ratios:
    require( 
        ((x ==0 || y ==0) && f == 0) ||
        (x == z && f == y) ||
        (y == z && f == x) ||
        constRatio(x, y, z, 2, 1, f) || // f = 2*x or f = x/2 (same for y)
        constRatio(x, y, z, 5, 1, f) || // f = 5*x or f = x/5 (same for y)
        constRatio(x, y, z, 2, 3, f) || // f = 2*x/3 or f = 3*x/2 (same for y)
        constRatio(x, y, z, 2, 7, f)    // f = 2*x/7 or f = 7*x/2 (same for y)
        );
    return f;
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
    axiom forall uint256 x. uint256 y1. uint256 y2.
        x >= ONE18() && y1 > y2 => _ghostPow(x, y1) >= _ghostPow(x, y2);
    axiom forall uint256 x. uint256 y1. uint256 y2.
        x < ONE18() && y1 > y2 => _ghostPow(x, y1) <= _ghostPow(x, y2);
    /// x1 > x2 && y > 0 => x1^y > x2^y
    axiom forall uint256 x1. uint256 x2. uint256 y.
        x1 > x2 => _ghostPow(x1, y) >= _ghostPow(x1, y);
}

function CVLPow(uint256 x, uint256 y) returns uint256 {
    if (y == 0) {return ONE18();}
    if (x == 0) {return 0;}
    return _ghostPow(x, y);
}
        