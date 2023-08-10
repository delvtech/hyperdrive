use ethers::types::{I256, U256};
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, int256, uint256};

#[test]
fn test_int256() {
    // simple cases
    assert_eq!(int256!(1), I256::from(1));
    assert_eq!(int256!(1_000), I256::from(1_000));
    assert_eq!(int256!(-1_000), I256::from(-1_000));

    // scientific notation
    assert_eq!(int256!(1e0), I256::from(1));
    assert_eq!(int256!(1e3), I256::from(1_000));
    assert_eq!(int256!(-1e18), -I256::from(10).pow(18));
    assert_eq!(
        int256!(-50_000e18),
        -I256::from(50_000) * I256::from(10).pow(18)
    );

    // decimal notation
    assert_eq!(int256!(1.0e1), I256::from(10));
    assert_eq!(int256!(1.1e18), I256::from(11) * I256::from(10).pow(17));
    assert_eq!(
        int256!(-333_333.555_555e18),
        -I256::from(333_333_555_555_u128) * I256::from(10).pow(12)
    );
}

#[test]
fn test_uint256() {
    // simple cases
    assert_eq!(uint256!(1), U256::from(1));
    assert_eq!(uint256!(1_000), U256::from(1_000));
    assert_eq!(uint256!(5_500_000_000), U256::from(5_500_000_000_u128));

    // scientific notation
    assert_eq!(uint256!(1e0), U256::from(1));
    assert_eq!(uint256!(1e3), U256::from(1_000));
    assert_eq!(
        uint256!(50_000e18),
        U256::from(50_000) * U256::from(10).pow(18.into())
    );

    // decimal notation
    assert_eq!(uint256!(1.0e1), U256::from(10));
    assert_eq!(
        uint256!(1.1e18),
        U256::from(11) * U256::from(10).pow(17.into())
    );
    assert_eq!(
        uint256!(333_333.555_555e18),
        U256::from(333_333_555_555_u128) * U256::from(10).pow(12.into())
    );
}

#[test]
fn test_fixed() {
    // simple cases
    assert_eq!(fixed!(1), FixedPoint::from(1));
    assert_eq!(fixed!(1_000), FixedPoint::from(1_000));
    assert_eq!(fixed!(5_500_000_000), FixedPoint::from(5_500_000_000_u128));

    // scientific notation
    assert_eq!(fixed!(1e0), FixedPoint::from(1));
    assert_eq!(fixed!(1e3), FixedPoint::from(1_000));
    assert_eq!(
        fixed!(50_000e18),
        FixedPoint::from(U256::from(50_000) * U256::from(10).pow(18.into()))
    );

    // decimal notation
    assert_eq!(fixed!(1.0e1), FixedPoint::from(10));
    assert_eq!(
        fixed!(1.1e18),
        FixedPoint::from(U256::from(11) * U256::from(10).pow(17.into())),
    );
    assert_eq!(
        fixed!(333_333.555_555e18),
        FixedPoint::from(U256::from(333_333_555_555_u128) * U256::from(10).pow(12.into()))
    );
}
