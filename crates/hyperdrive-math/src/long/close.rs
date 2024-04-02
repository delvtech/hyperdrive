use ethers::types::U256;
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

use crate::{State, YieldSpace};

impl State {
    fn calculate_close_long_flat_plus_curve<F: Into<FixedPoint>>(
        &self,
        bond_amount: F,
        maturity_time: U256,
        current_time: U256,
    ) -> FixedPoint {
        let bond_amount = bond_amount.into();
        let normalized_time_remaining =
            self.calculate_normalized_time_remaining(maturity_time, current_time);

        // Calculate the flat part of the trade
        let flat = bond_amount.mul_div_down(
            fixed!(1e18) - normalized_time_remaining,
            self.vault_share_price(),
        );

        // Calculate the curve part of the trade
        let curve = if normalized_time_remaining > fixed!(0) {
            let curve_bonds_in = bond_amount * normalized_time_remaining;
            self.calculate_shares_out_given_bonds_in_down(curve_bonds_in)
        } else {
            fixed!(0)
        };

        flat + curve
    }

    /// Calculates the amount of shares the trader will receive after fees for closing a long
    pub fn calculate_close_long<F: Into<FixedPoint>>(
        &self,
        bond_amount: F,
        maturity_time: U256,
        current_time: U256,
    ) -> FixedPoint {
        let bond_amount = bond_amount.into();

        // Subtract the fees from the trade
        self.calculate_close_long_flat_plus_curve(bond_amount, maturity_time, current_time)
            - self.close_long_curve_fee(bond_amount, maturity_time, current_time)
            - self.close_long_flat_fee(bond_amount, maturity_time, current_time)
    }
}

#[cfg(test)]
mod tests {
    use std::panic;

    use eyre::Result;
    use rand::{thread_rng, Rng};
    use test_utils::{chain::TestChainWithMocks, constants::FAST_FUZZ_RUNS};

    use super::*;
    use crate::State;

    #[tokio::test]
    async fn fuzz_calculate_close_long_flat_plus_curve() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_hyperdrive_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let in_ = rng.gen_range(fixed!(0)..=state.effective_share_reserves());
            let maturity_time = state.checkpoint_duration();
            let current_time = rng.gen_range(fixed!(0)..=maturity_time);
            let normalized_time_remaining = state
                .calculate_normalized_time_remaining(maturity_time.into(), current_time.into());
            let actual = panic::catch_unwind(|| {
                state.calculate_close_long_flat_plus_curve(
                    in_,
                    maturity_time.into(),
                    current_time.into(),
                )
            });
            match mock
                .calculate_close_long(
                    state.effective_share_reserves().into(),
                    state.bond_reserves().into(),
                    in_.into(),
                    normalized_time_remaining.into(),
                    state.t().into(),
                    state.c().into(),
                    state.mu().into(),
                )
                .call()
                .await
            {
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected.2)),
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }
}
