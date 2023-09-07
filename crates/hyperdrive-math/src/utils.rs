use ethers::types::{I256, U256};
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, uint256};

pub fn get_time_stretch(mut rate: FixedPoint) -> FixedPoint {
    rate = (U256::from(rate) * uint256!(100)).into();
    let time_stretch = fixed!(5.24592e18) / (fixed!(0.04665e18) * rate);
    fixed!(1e18) / time_stretch
}

pub fn get_effective_share_reserves(
    share_reserves: FixedPoint,
    share_adjustment: I256,
) -> FixedPoint {
    let effective_share_reserves = I256::from(share_reserves) - share_adjustment;
    if effective_share_reserves < I256::from(0) {
        panic!("effective share reserves cannot be negative");
    }
    effective_share_reserves.into()
}
