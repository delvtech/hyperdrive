use fixed_point::FixedPoint;

use crate::{State, YieldSpace};

impl State {
    /// Gets the long amount that will be opened for a given base amount.
    ///
    /// The long amount $y(x)$ that a trader will receive is given by:
    ///
    /// $$
    /// y(x) = y_{*}(x) - c(x)
    /// $$
    ///
    /// Where $y_{*}(x)$ is the amount of long that would be opened if there was
    /// no curve fee and [$c(x)$](long_curve_fee) is the curve fee. $y_{*}(x)$
    /// is given by:
    ///
    /// $$
    /// y_{*}(x) = y - \left(
    ///                k - \tfrac{c}{\mu} \cdot \left(
    ///                    \mu \cdot \left( z + \tfrac{x}{c}
    ///                \right) \right)^{1 - t_s}
    ///            \right)^{\tfrac{1}{1 - t_s}}
    /// $$
    pub fn calculate_open_long<F: Into<FixedPoint>>(&self, base_amount: F) -> FixedPoint {
        let base_amount = base_amount.into();
        let long_amount =
            self.calculate_bonds_out_given_shares_in_down(base_amount / self.share_price());
        long_amount - self.open_long_curve_fees(base_amount)
    }

    #[deprecated(since = "0.4.0", note = "please use `calculate_open_long` instead")]
    pub fn get_long_amount<F: Into<FixedPoint>>(&self, base_amount: F) -> FixedPoint {
        self.calculate_open_long(base_amount)
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
