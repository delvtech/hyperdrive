use ethers::types::U256;
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

use crate::{yield_space::get_spot_price, State, YieldSpace};

/// Gets the curve fee paid by the trader when they open a short.
pub fn open_short_curve_fee(
    curve_fee: FixedPoint,
    short_amount: FixedPoint,
    spot_price: FixedPoint,
) -> FixedPoint {
    curve_fee * (fixed!(1e18) - spot_price) * short_amount
}

/// Gets the governance fee paid by the trader when they open a short.
pub fn open_short_governance_fee(
    curve_fee: FixedPoint,
    governance_lp_fee: FixedPoint,
    short_amount: FixedPoint,
    spot_price: FixedPoint,
) -> FixedPoint {
    governance_lp_fee * open_short_curve_fee(curve_fee, short_amount, spot_price)
}

/// Gets the curve fee paid by shorts for a given bond amount.
/// Returns the fee in shares
pub fn close_short_curve_fee(
    ze: FixedPoint,
    y: FixedPoint,
    c: FixedPoint,
    mu: FixedPoint,
    t: FixedPoint,
    curve_fee: FixedPoint,
    bond_amount: FixedPoint,
    normalized_time_remaining: FixedPoint,
) -> FixedPoint {
    // ((1 - p) * phi_curve * d_y * t) / c
    curve_fee
        * (fixed!(1e18) - get_spot_price(ze, y, mu, t))
        * bond_amount.mul_div_down(normalized_time_remaining, c)
}

/// Gets the flat fee paid by shorts for a given bond amount
/// Returns the fee in shares
pub fn close_short_flat_fee(
    c: FixedPoint,
    flat_fee: FixedPoint,
    bond_amount: FixedPoint,
    normalized_time_remaining: FixedPoint,
) -> FixedPoint {
    // flat fee = (d_y * (1 - t) * phi_flat) / c
    bond_amount.mul_div_down(fixed!(1e18) - normalized_time_remaining, c) * flat_fee
}

impl State {
    /// Gets the curve fee paid by the trader when they open a short.
    pub fn open_short_curve_fee(
        &self,
        short_amount: FixedPoint,
        spot_price: FixedPoint,
    ) -> FixedPoint {
        open_short_curve_fee(self.curve_fee(), short_amount, spot_price)
    }

    /// Gets the governance fee paid by the trader when they open a short.
    pub fn open_short_governance_fee(
        &self,
        short_amount: FixedPoint,
        spot_price: FixedPoint,
    ) -> FixedPoint {
        open_short_governance_fee(
            self.curve_fee(),
            self.governance_lp_fee(),
            short_amount,
            spot_price,
        )
    }

    /// Gets the curve fee paid by shorts for a given bond amount.
    /// Returns the fee in shares
    pub fn close_short_curve_fee(
        &self,
        bond_amount: FixedPoint,
        maturity_time: U256,
        current_time: U256,
    ) -> FixedPoint {
        let normalized_time_remaining =
            self.calculate_normalized_time_remaining(maturity_time, current_time);

        // ((1 - p) * phi_curve * d_y * t) / c
        close_short_curve_fee(
            self.ze(),
            self.y(),
            self.c(),
            self.mu(),
            self.t(),
            self.curve_fee(),
            bond_amount,
            normalized_time_remaining,
        )
    }

    /// Gets the flat fee paid by shorts for a given bond amount
    /// Returns the fee in shares
    pub fn close_short_flat_fee(
        &self,
        bond_amount: FixedPoint,
        maturity_time: U256,
        current_time: U256,
    ) -> FixedPoint {
        let normalized_time_remaining =
            self.calculate_normalized_time_remaining(maturity_time, current_time);
        // flat fee = (d_y * (1 - t) * phi_flat) / c
        close_short_flat_fee(
            self.c(),
            self.flat_fee(),
            bond_amount,
            normalized_time_remaining,
        )
    }
}
