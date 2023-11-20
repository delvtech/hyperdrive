use ethers::types::I256;
use eyre::Result;
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

use crate::{get_effective_share_reserves, State, YieldSpace};

impl State {
    /// Gets the minimum price that the pool can support.
    ///
    /// YieldSpace intersects the y-axis with a finite slope, so there is a
    /// minimum price that the pool can support. This is the price at which the
    /// share reserves are equal to the minimum share reserves.
    ///
    /// We can solve for the bond reserves $y_{max}$ implied by the share reserves
    /// being equal to $z_{min}$ using the current k value:
    ///
    /// $$
    /// k = \tfrac{c}{\mu} \cdot \left( \mu \cdot z_{min} \right)^{1 - t_s} + y_{max}^{1 - t_s} \\
    /// \implies \\
    /// y_{max} = \left( k - \tfrac{c}{\mu} \cdot \left( \mu \cdot z_{min} \right)^{1 - t_s} \right)^{\tfrac{1}{1 - t_s}}
    /// $$
    ///
    /// From there, we can calculate the spot price as normal as:
    ///
    /// $$
    /// p = \left( \tfrac{\mu \cdot z_{min}}{y_{max}} \right)^{t_s}
    /// $$
    pub fn get_min_price(&self) -> FixedPoint {
        let y_max = (self.k_up()
            - (self.share_price() / self.initial_share_price())
                * (self.initial_share_price() * self.minimum_share_reserves())
                    .pow(fixed!(1e18) - self.time_stretch()))
        .pow(fixed!(1e18).div_up(fixed!(1e18) - self.time_stretch()));
        ((self.initial_share_price() * self.minimum_share_reserves()) / y_max)
            .pow(self.time_stretch())
    }

    /// Gets the amount of base the trader will need to deposit for a short of
    /// a given size.
    ///
    /// The short deposit is made up of several components:
    /// - The long's fixed rate (without considering fees): $\Delta y - c \cdot \Delta
    /// - The curve fee: $c \cdot (1 - p) \cdot \Delta y$
    /// - The backpaid short interest: $(c - c_0) \cdot \Delta y$
    /// - The flat fee: $f \cdot \Delta y$
    ///
    /// Putting these components together, we can write out the short deposit
    /// function as:
    ///
    /// $$
    /// D(x) = \Delta y - (c \cdot P(x) - \phi_{curve} \cdot (1 - p) \cdot \Delta y)
    ///        + (c - c_0) \cdot \tfrac{\Delta y}{c_0} + \phi_{flat} \cdot \Delta y \\
    ///      = \tfrac{c}{c_0} \cdot \Delta y - (c \cdot P(x) - \phi_{curve} \cdot (1 - p) \cdot \Delta y)
    ///        + \phi_{flat} \cdot \Delta y
    /// $$
    ///
    /// $x$ is the number of bonds being shorted and $P(x)$ is the amount of
    /// shares the curve says the LPs need to pay the shorts (i.e. the LP
    /// principal).
    pub fn get_short_deposit(
        &self,
        short_amount: FixedPoint,
        spot_price: FixedPoint,
        mut open_share_price: FixedPoint,
    ) -> Result<FixedPoint> {
        // If the open share price hasn't been set, we use the current share
        // price, since this is what will be set as the checkpoint share price
        // in the next transaction.
        if open_share_price == fixed!(0) {
            open_share_price = self.share_price();
        }

        // NOTE: The order of additions and subtractions is important to avoid underflows.
        Ok(
            short_amount.mul_div_down(self.share_price(), open_share_price)
                + self.flat_fee() * short_amount
                + self.curve_fee() * (fixed!(1e18) - spot_price) * short_amount
                - self.share_price() * self.short_principal(short_amount)?,
        )
    }

    /// Gets the amount of short principal that the LPs need to pay to back a
    /// short before fees are taken into consideration, $P(x)$.
    ///
    /// Let the LP principal that backs $x$ shorts be given by $P(x)$. We can
    /// solve for this in terms of $x$ using the YieldSpace invariant:
    ///
    /// $$
    /// k = \tfrac{c}{\mu} \cdot (\mu \cdot (z - P(x)))^{1 - t_s} + (y + x)^{1 - t_s} \\
    /// \implies \\
    /// P(x) = z - \tfrac{1}{\mu} \cdot (\tfrac{\mu}{c} \cdot (k - (y + x)^{1 - t_s}))^{\tfrac{1}{1 - t_s}}
    /// $$
    pub fn short_principal(&self, short_amount: FixedPoint) -> Result<FixedPoint> {
        self.calculate_shares_out_given_bonds_in_down_safe(short_amount)
    }
}

#[cfg(test)]
mod tests {
    use std::panic;

    use ethers::types::U256;
    use eyre::Result;
    use hyperdrive_wrappers::wrappers::{
        i_hyperdrive::Checkpoint, mock_hyperdrive_math::MaxTradeParams,
    };
    use rand::{thread_rng, Rng};
    use test_utils::{
        agent::Agent,
        chain::{Chain, TestChain, TestChainWithMocks},
        constants::{FAST_FUZZ_RUNS, FUZZ_RUNS},
    };
    use tracing_test::traced_test;

    use super::*;

    /// This test differentially fuzzes the `get_max_short` function against the
    /// Solidity analogue `calculateMaxShort`. `calculateMaxShort` doesn't take
    /// a trader's budget into account, so it only provides a subset of
    /// `get_max_short`'s functionality. With this in mind, we provide
    /// `get_max_short` with a budget of `U256::MAX` to ensure that the two
    /// functions are equivalent.
    #[tokio::test]
    async fn fuzz_get_max_short_no_budget() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let checkpoint_exposure = {
                let value = rng.gen_range(fixed!(0)..=fixed!(10_000_000e18));
                if rng.gen() {
                    -I256::from(value)
                } else {
                    I256::from(value)
                }
            };
            let max_iterations = 7;
            let actual = panic::catch_unwind(|| {
                state.get_max_short(
                    U256::MAX,
                    fixed!(0),
                    checkpoint_exposure,
                    None,
                    Some(max_iterations),
                )
            });
            match chain
                .mock_hyperdrive_math()
                .calculate_max_short(
                    MaxTradeParams {
                        share_reserves: state.info.share_reserves,
                        bond_reserves: state.info.bond_reserves,
                        longs_outstanding: state.info.longs_outstanding,
                        long_exposure: state.info.long_exposure,
                        share_adjustment: state.info.share_adjustment,
                        time_stretch: state.config.time_stretch,
                        share_price: state.info.share_price,
                        initial_share_price: state.config.initial_share_price,
                        minimum_share_reserves: state.config.minimum_share_reserves,
                        curve_fee: state.config.fees.curve,
                        governance_fee: state.config.fees.governance,
                    },
                    checkpoint_exposure,
                    max_iterations.into(),
                )
                .call()
                .await
            {
                Ok(expected) => {
                    assert_eq!(actual.unwrap(), FixedPoint::from(expected));
                }
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }
}
