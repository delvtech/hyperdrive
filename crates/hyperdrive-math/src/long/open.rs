use ethers::types::I256;
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, int256};

use crate::State;
use crate::YieldSpace;

impl State {
    /// Gets the pool's max spot price.
    ///
    /// Hyperdrive has assertions to ensure that traders don't purchase bonds at
    /// negative interest rates. The maximum spot price that longs can push the
    /// market to is given by:
    ///
    /// $$
    /// p_max = \frac{1}{1 + \phi_c * \left( p_0^{-1} - 1 \right)}
    /// $$
    pub fn get_max_spot_price(&self) -> FixedPoint {
        fixed!(1e18)
            / (fixed!(1e18)
                + self
                    .curve_fee()
                    .mul_up(fixed!(1e18).div_up(self.get_spot_price()) - fixed!(1e18)))
    }

    /// Gets the spot price after opening the long on the YieldSpace curve and
    /// before calculating the fees.
    pub fn get_spot_price_after_long(&self, long_amount: FixedPoint) -> FixedPoint {
        let mut state: State = self.clone();
        state.info.bond_reserves -= state
            .calculate_bonds_out_given_shares_in_down(long_amount / state.share_price())
            .into();
        state.info.share_reserves += (long_amount / state.share_price()).into();
        state.get_spot_price()
    }
}
