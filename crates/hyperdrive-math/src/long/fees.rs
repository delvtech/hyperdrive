use ethers::types::I256;
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, int256};

use crate::{State, YieldSpace};

impl State {
    /// Gets the curve fee paid by longs for a given base amount.
    /// Returns the fee in bonds
    pub fn open_long_curve_fees_given_base(&self, base_amount: FixedPoint) -> FixedPoint {
        // curve fee = ((1 / p) - 1) * phi_curve * dz
        self.curve_fee() * ((fixed!(1e18) / self.get_spot_price()) - fixed!(1e18)) * base_amount
    }

    /// Gets the governance fee paid by longs for a given base amount.
    ///
    /// Unlike the [curve fee](long_curve_fee) which is paid in bonds, the
    /// governance fee is paid in base.
    /// Returns the fee in base
    pub fn open_long_governance_fee_given_base(&self, base_amount: FixedPoint) -> FixedPoint {
        self.governance_fee() * self.get_spot_price() * self.open_long_curve_fees_given_base(base_amount)
    }

    /// Gets the flat fee paid by longs for a given bond amount.
    /// Returns the fee in shares
    pub fn close_long_curve_fee_given_bonds(&self, bond_amount: FixedPoint, normalized_time_remaining: FixedPoint) -> FixedPoint {
        // ((1 - p) * phi_curve * d_y * t) / c
        self.curve_fee()*(fixed!(1e18) - self.get_spot_price())*bond_amount.mul_div_down(normalized_time_remaining, self.share_price())
    }

    /// Gets the flat fee paid by longs for a given bond amount
    /// Returns the fee in shares
    pub fn close_long_flat_fee_given_bonds(&self, bond_amount: FixedPoint, normalized_time_remaining: FixedPoint) -> FixedPoint {
        // flat fee = (d_y * (1 - t) * phi_flat) / c
        bond_amount.mul_div_down(fixed!(1e18) - normalized_time_remaining, self.share_price()) * self.flat_fee()
    }
}
