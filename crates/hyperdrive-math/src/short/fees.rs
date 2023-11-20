use ethers::types::I256;
use eyre::Result;
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

use crate::State;
use crate::{get_effective_share_reserves, YieldSpace};

impl State {
    /// Gets the curve fee paid by the trader when they open a short.
    pub fn short_curve_fee(&self, short_amount: FixedPoint, spot_price: FixedPoint) -> FixedPoint {
        self.curve_fee() * (fixed!(1e18) - spot_price) * short_amount
    }

    /// Gets the governance fee paid by the trader when they open a short.
    pub fn short_governance_fee(&self, short_amount: FixedPoint, spot_price: FixedPoint) -> FixedPoint {
        self.governance_fee() * self.short_curve_fee(short_amount, spot_price)
    }
}