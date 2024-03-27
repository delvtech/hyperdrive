use ethers::types::U256;
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

use crate::{yield_space::get_spot_price, State, YieldSpace};

/// Gets the curve fee paid by longs for a given base amount.
///
/// The curve fee $c(x)$ paid by longs is paid in bonds and is given by:
///
/// $$
/// c(x) = \phi_{c} \cdot \left( \tfrac{1}{p} - 1 \right) \cdot x
/// $$
pub fn open_long_curve_fees(
    ze: FixedPoint,
    y: FixedPoint,
    mu: FixedPoint,
    t: FixedPoint,
    curve_fee: FixedPoint,
    base_amount: FixedPoint,
) -> FixedPoint {
    curve_fee * ((fixed!(1e18) / get_spot_price(ze, y, mu, t)) - fixed!(1e18)) * base_amount
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
pub fn open_long_governance_fee(
    ze: FixedPoint,
    y: FixedPoint,
    mu: FixedPoint,
    t: FixedPoint,
    curve_fee: FixedPoint,
    governance_lp_fee: FixedPoint,
    base_amount: FixedPoint,
) -> FixedPoint {
    governance_lp_fee
        * get_spot_price(ze, y, mu, t)
        * open_long_curve_fees(ze, y, mu, t, curve_fee, base_amount)
}

/// Gets the curve fee paid by longs for a given bond amount.
/// Returns the fee in shares
pub fn close_long_curve_fee(
    ze: FixedPoint,
    y: FixedPoint,
    c: FixedPoint,
    mu: FixedPoint,
    t: FixedPoint,
    curve_fee: FixedPoint,
    bond_amount: FixedPoint,
    normalized_time_remaining: FixedPoint,
) -> FixedPoint {
    // curve_fee = ((1 - p) * phi_curve * d_y * t) / c
    curve_fee
        * (fixed!(1e18) - get_spot_price(ze, y, mu, t))
        * bond_amount.mul_div_down(normalized_time_remaining, c)
}

/// Gets the flat fee paid by longs for a given bond amount
/// Returns the fee in shares
pub fn close_long_flat_fee(
    c: FixedPoint,
    bond_amount: FixedPoint,
    normalized_time_remaining: FixedPoint,
    flat_fee: FixedPoint,
) -> FixedPoint {
    // flat_fee = (d_y * (1 - t) * phi_flat) / c
    bond_amount.mul_div_down(fixed!(1e18) - normalized_time_remaining, c) * flat_fee
}

impl State {
    /// Gets the curve fee paid by longs for a given base amount.
    ///
    /// The curve fee $c(x)$ paid by longs is paid in bonds and is given by:
    ///
    /// $$
    /// c(x) = \phi_{c} \cdot \left( \tfrac{1}{p} - 1 \right) \cdot x
    /// $$
    pub fn open_long_curve_fees(&self, base_amount: FixedPoint) -> FixedPoint {
        open_long_curve_fees(
            self.ze(),
            self.y(),
            self.mu(),
            self.t(),
            self.curve_fee(),
            base_amount,
        )
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
        open_long_governance_fee(
            self.ze(),
            self.y(),
            self.mu(),
            self.t(),
            self.curve_fee(),
            self.governance_lp_fee(),
            base_amount,
        )
    }

    /// Gets the curve fee paid by longs for a given bond amount.
    /// Returns the fee in shares
    pub fn close_long_curve_fee(
        &self,
        bond_amount: FixedPoint,
        maturity_time: U256,
        current_time: U256,
    ) -> FixedPoint {
        let normalized_time_remaining =
            self.calculate_normalized_time_remaining(maturity_time, current_time);
        // curve_fee = ((1 - p) * phi_curve * d_y * t) / c
        self.curve_fee()
            * (fixed!(1e18) - self.get_spot_price())
            * bond_amount.mul_div_down(normalized_time_remaining, self.vault_share_price())
    }

    /// Gets the flat fee paid by longs for a given bond amount
    /// Returns the fee in shares
    pub fn close_long_flat_fee(
        &self,
        bond_amount: FixedPoint,
        maturity_time: U256,
        current_time: U256,
    ) -> FixedPoint {
        let normalized_time_remaining =
            self.calculate_normalized_time_remaining(maturity_time, current_time);
        // flat_fee = (d_y * (1 - t) * phi_flat) / c
        bond_amount.mul_div_down(
            fixed!(1e18) - normalized_time_remaining,
            self.vault_share_price(),
        ) * self.flat_fee()
    }
}
