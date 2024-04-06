use ethers::types::U256;
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

use crate::State;

impl State {
    /// Calculates the curve fee paid by the trader when they open a short.
    pub fn open_short_curve_fee(
        &self,
        short_amount: FixedPoint,
        spot_price: FixedPoint,
    ) -> FixedPoint {
        self.curve_fee() * (fixed!(1e18) - spot_price) * short_amount
    }

    /// Calculates the governance fee paid by the trader when they open a short.
    pub fn open_short_governance_fee(
        &self,
        short_amount: FixedPoint,
        spot_price: FixedPoint,
    ) -> FixedPoint {
        self.governance_lp_fee() * self.open_short_curve_fee(short_amount, spot_price)
    }

    /// Calculates the curve fee paid by shorts for a given bond amount.
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
        self.curve_fee()
            * (fixed!(1e18) - self.calculate_spot_price())
            * bond_amount.mul_div_down(normalized_time_remaining, self.vault_share_price())
    }

    // Calculate the curve portion of the governance fee for close shorts
    // NOTE: Round down to underestimate the governance curve fee
    // TODO: avoid duplicate calculation of close short curve fee
    // https://github.com/delvtech/hyperdrive/issues/943
    pub fn close_short_governance_fee(
        &self,
        bond_amount: FixedPoint,
        maturity_time: U256,
        current_time: U256,
    ) -> FixedPoint {
        self.close_short_curve_fee(bond_amount, maturity_time, current_time)
            .mul_down(self.governance_lp_fee())
    }

    /// Calculates the flat fee paid by shorts for a given bond amount
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
        bond_amount.mul_div_down(
            fixed!(1e18) - normalized_time_remaining,
            self.vault_share_price(),
        ) * self.flat_fee()
    }
}
