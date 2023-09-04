use ethers::types::U256;
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, uint256};

pub fn get_time_stretch(mut rate: FixedPoint) -> FixedPoint {
    rate = (U256::from(rate) * uint256!(100)).into();
    let time_stretch = fixed!(5.24592e18) / (fixed!(0.04665e18) * rate);
    fixed!(1e18) / time_stretch
}
