
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

use crate::{State};

impl State {
    /// Gets the curve fee paid by longs for a given base amount.
    ///
    /// The curve fee $c(x)$ paid by longs is paid in bonds and is given by:
    ///
    /// $$
    /// c(x) = \phi_{c} \cdot \left( \tfrac{1}{p} - 1 \right) \cdot x
    /// $$
    pub fn open_long_curve_fees(&self, base_amount: FixedPoint) -> FixedPoint {
        // curve fee = ((1 / p) - 1) * phi_curve * dz
        self.curve_fee() * ((fixed!(1e18) / self.get_spot_price()) - fixed!(1e18)) * base_amount
    }

    /// Gets the governance fee paid by longs for a given base amount.
    ///
    /// Unlike the [curve fee](long_curve_fee) which is paid in bonds, the
    /// governance fee is paid in base. The governance fee $g(x)$ paid by longs
    /// is given by:
    ///
    /// $$
    /// g(x) = \phi_{g} \cdot p \cdot c(x)
    /// $$
    pub fn open_long_governance_fee(&self, base_amount: FixedPoint) -> FixedPoint {
        self.governance_fee() * self.get_spot_price() * self.open_long_curve_fees(base_amount)
    }

    /// Gets the curve fee paid by longs for a given bond amount.
    /// Returns the fee in shares
    pub fn close_long_curve_fee(
        &self,
        bond_amount: FixedPoint,
        normalized_time_remaining: FixedPoint,
    ) -> FixedPoint {
        // ((1 - p) * phi_curve * d_y * t) / c
        self.curve_fee()
            * (fixed!(1e18) - self.get_spot_price())
            * bond_amount.mul_div_down(normalized_time_remaining, self.share_price())
    }

    /// Gets the flat fee paid by longs for a given bond amount
    /// Returns the fee in shares
    pub fn close_long_flat_fee(
        &self,
        bond_amount: FixedPoint,
        normalized_time_remaining: FixedPoint,
    ) -> FixedPoint {
        // flat fee = (d_y * (1 - t) * phi_flat) / c
        bond_amount.mul_div_down(fixed!(1e18) - normalized_time_remaining, self.share_price())
            * self.flat_fee()
    }
}
