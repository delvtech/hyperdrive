use ethers::types::I256;
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, int256};

use crate::{State, YieldSpace};

impl State {
    fn _calculate_close_short<F: Into<FixedPoint>>(
        &self,
        bond_amount: F,
        normalized_time_remaining: F,
    ) -> FixedPoint {
        let bond_amount = bond_amount.into();
        let normalized_time_remaining = normalized_time_remaining.into();

        // Calculate the flat part of the trade
        let flat =
            bond_amount.mul_div_down(fixed!(1e18) - normalized_time_remaining, self.share_price());

        // Calculate the curve part of the trade
        let curve = if normalized_time_remaining > fixed!(0e18) {
            let curve_bonds_in = bond_amount * normalized_time_remaining;
            self.calculate_shares_in_given_bonds_out_up(curve_bonds_in)
        } else {
            fixed!(0e18)
        };

        flat + curve
    }

    // Calculates the proceeds in shares of closing a short position.
    fn calculate_short_proceeds(
        &self,
        bond_amount: FixedPoint,
        share_amount: FixedPoint,
        open_share_price: FixedPoint,
        close_share_price: FixedPoint,
        share_price: FixedPoint,
        flat_fee: FixedPoint,
    ) -> FixedPoint {
        let mut bond_factor = bond_amount.mul_div_down(
            close_share_price,
            // We round up here do avoid overestimating the share proceeds.
            open_share_price.mul_up(share_price),
        );
        bond_factor += bond_amount.mul_div_down(flat_fee, share_price);

        let share_proceeds = if bond_factor > share_amount {
            // proceeds = (c1 / c0 * c) * dy - dz
            bond_factor - share_amount
        } else {
            fixed!(0e18)
        };
        share_proceeds
    }

    /// Gets the amount of shares the trader will receive after fees for closing a long
    pub fn calculate_close_short<F: Into<FixedPoint>>(
        &self,
        bond_amount: F,
        open_share_price: F,
        close_share_price: F,
        normalized_time_remaining: F,
    ) -> FixedPoint {
        let bond_amount = bond_amount.into();
        let open_share_price = open_share_price.into();
        let close_share_price = close_share_price.into();
        let normalized_time_remaining = normalized_time_remaining.into();

        // Calculate flat + curve and subtract the fees from the trade.
        let share_reserves_delta = self
            ._calculate_close_short(bond_amount, normalized_time_remaining)
            + self.close_short_curve_fee(bond_amount, normalized_time_remaining)
            + self.close_short_flat_fee(bond_amount, normalized_time_remaining);

        // Calculate the share proceeds owed to the short.
        self.calculate_short_proceeds(
            bond_amount,
            share_reserves_delta,
            open_share_price,
            close_share_price,
            self.share_price(),
            self.flat_fee(),
        )
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
    async fn fuzz_calculate_short_proceeds() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_hyperdrive_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let bond_amount = rng.gen_range(fixed!(0e18)..=state.bond_reserves());
            let share_amount = rng.gen_range(fixed!(0e18)..=bond_amount);
            let open_share_price = rng.gen_range(fixed!(0e18)..=state.share_price());
            let actual = panic::catch_unwind(|| {
                state.calculate_short_proceeds(
                    bond_amount,
                    share_amount,
                    open_share_price,
                    state.share_price(),
                    state.share_price(),
                    state.flat_fee(),
                )
            });
            match mock
                .calculate_short_proceeds(
                    bond_amount.into(),
                    share_amount.into(),
                    open_share_price.into(),
                    state.share_price().into(),
                    state.share_price().into(),
                    state.flat_fee().into(),
                )
                .call()
                .await
            {
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected)),
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_calculate_close_short() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_hyperdrive_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let in_ = rng.gen_range(fixed!(0e18)..=state.bond_reserves());
            let normalized_time_remaining = rng.gen_range(fixed!(0e18)..=fixed!(1e18));
            let actual = panic::catch_unwind(|| {
                state._calculate_close_short(in_, normalized_time_remaining)
            });
            match mock
                .calculate_close_short(
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
