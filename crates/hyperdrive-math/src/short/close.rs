use ethers::types::U256;
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

use crate::{State, YieldSpace};

impl State {
    fn calculate_close_short_flat<F: Into<FixedPoint>>(
        &self,
        bond_amount: F,
        maturity_time: U256,
        current_time: U256,
    ) -> FixedPoint {
        // NOTE: We overestimate the trader's share payment to avoid sandwiches.
        let bond_amount = bond_amount.into();
        let normalized_time_remaining =
            self.calculate_normalized_time_remaining(maturity_time, current_time);
        bond_amount.mul_div_up(
            fixed!(1e18) - normalized_time_remaining,
            self.vault_share_price(),
        )
    }

    fn calculate_close_short_curve<F: Into<FixedPoint>>(
        &self,
        bond_amount: F,
        maturity_time: U256,
        current_time: U256,
    ) -> FixedPoint {
        let bond_amount = bond_amount.into();
        let normalized_time_remaining =
            self.calculate_normalized_time_remaining(maturity_time, current_time);
        if normalized_time_remaining > fixed!(0) {
            // NOTE: Round the `shareCurveDelta` up to overestimate the share
            // payment.
            //
            let curve_bonds_in = bond_amount.mul_up(normalized_time_remaining);
            self.calculate_shares_in_given_bonds_out_up_safe(curve_bonds_in)
                .unwrap()
        } else {
            fixed!(0)
        }
    }

    fn calculate_close_short_flat_plus_curve<F: Into<FixedPoint>>(
        &self,
        bond_amount: F,
        maturity_time: U256,
        current_time: U256,
    ) -> FixedPoint {
        let bond_amount = bond_amount.into();
        // Calculate the flat part of the trade
        let flat = self.calculate_close_short_flat(bond_amount, maturity_time, current_time);
        // Calculate the curve part of the trade
        let curve = self.calculate_close_short_curve(bond_amount, maturity_time, current_time);

        flat + curve
    }

    // Calculates the proceeds in shares of closing a short position.
    fn calculate_short_proceeds(
        &self,
        bond_amount: FixedPoint,
        share_amount: FixedPoint,
        open_vault_share_price: FixedPoint,
        close_vault_share_price: FixedPoint,
        vault_share_price: FixedPoint,
        flat_fee: FixedPoint,
    ) -> FixedPoint {
        let mut bond_factor = bond_amount
            .mul_div_down(
                close_vault_share_price,
                // We round up here do avoid overestimating the share proceeds.
                open_vault_share_price,
            )
            .div_down(vault_share_price);
        bond_factor += bond_amount.mul_div_down(flat_fee, vault_share_price);

        if bond_factor > share_amount {
            // proceeds = (c1 / c0 * c) * dy - dz
            bond_factor - share_amount
        } else {
            fixed!(0)
        }
    }

    /// Since traders pay a curve fee when they close shorts on Hyperdrive,
    /// it is possible for traders to receive a negative interest rate even
    /// if curve's spot price is less than or equal to 1.
    //
    /// Given the curve fee `phi_c` and the starting spot price `p_0`, the
    /// maximum spot price is given by:
    /// $$
    /// p_max = 1 - phi_c * (1 - p_0)
    /// $$
    fn calculate_close_short_max_spot_price(&self) -> FixedPoint {
        fixed!(1e18)
            - self
                .curve_fee()
                .mul_up(fixed!(1e18) - self.calculate_spot_price())
    }

    /// Calculates the amount of shares the trader will receive after fees for closing a short
    pub fn calculate_close_short<F: Into<FixedPoint>>(
        &self,
        bond_amount: F,
        open_vault_share_price: F,
        close_vault_share_price: F,
        maturity_time: U256,
        current_time: U256,
    ) -> FixedPoint {
        let bond_amount = bond_amount.into();
        let open_vault_share_price = open_vault_share_price.into();
        let close_vault_share_price = close_vault_share_price.into();

        if bond_amount < self.config.minimum_transaction_amount.into() {
            // TODO would be nice to return a `Result` here instead of a panic.
            panic!("MinimumTransactionAmount: Input amount too low");
        }

        // Ensure that the trader didn't purchase bonds at a negative interest
        // rate after accounting for fees
        let share_curve_delta =
            self.calculate_close_short_curve(bond_amount, maturity_time, current_time);
        let bond_reserves_delta = bond_amount
            .mul_up(self.calculate_normalized_time_remaining(maturity_time, current_time));
        let short_curve_spot_price = {
            let mut state: State = self.clone();
            state.info.bond_reserves -= bond_reserves_delta.into();
            state.info.share_reserves += share_curve_delta.into();
            state.calculate_spot_price()
        };
        let max_spot_price = self.calculate_close_short_max_spot_price();
        if short_curve_spot_price > max_spot_price {
            // TODO would be nice to return a `Result` here instead of a panic.
            panic!("InsufficientLiquidity: Negative Interest");
        }

        // Ensure ending spot price is less than one
        let share_curve_delta_with_fees = share_curve_delta
            + self.close_short_curve_fee(bond_amount, maturity_time, current_time)
            - self.close_short_governance_fee(bond_amount, maturity_time, current_time);
        let share_curve_delta_with_fees_spot_price = {
            let mut state: State = self.clone();
            state.info.bond_reserves -= bond_reserves_delta.into();
            state.info.share_reserves += share_curve_delta_with_fees.into();
            state.calculate_spot_price()
        };
        if share_curve_delta_with_fees_spot_price > fixed!(1e18) {
            // TODO would be nice to return a `Result` here instead of a panic.
            panic!("InsufficientLiquidity: Negative Interest");
        }

        // Now calculate short proceeds
        // TODO we've already calculated a couple of internal variables needed by this function,
        // rework to avoid recalculating the curve and bond reserves
        // https://github.com/delvtech/hyperdrive/issues/943
        let share_reserves_delta =
            self.calculate_close_short_flat_plus_curve(bond_amount, maturity_time, current_time);
        // Calculate flat + curve and subtract the fees from the trade.
        let share_reserves_delta_with_fees = share_reserves_delta
            + self.close_short_curve_fee(bond_amount, maturity_time, current_time)
            + self.close_short_flat_fee(bond_amount, maturity_time, current_time);

        // Calculate the share proceeds owed to the short.
        self.calculate_short_proceeds(
            bond_amount,
            share_reserves_delta_with_fees,
            open_vault_share_price,
            close_vault_share_price,
            self.vault_share_price(),
            self.flat_fee(),
        )
    }
}

#[cfg(test)]
mod tests {
    use std::panic;

    use eyre::Result;
    use rand::{thread_rng, Rng};
    use test_utils::{chain::TestChain, constants::FAST_FUZZ_RUNS};

    use super::*;

    #[tokio::test]
    async fn fuzz_calculate_short_proceeds() -> Result<()> {
        let chain = TestChain::new().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let bond_amount = rng.gen_range(fixed!(0)..=state.bond_reserves());
            let share_amount = rng.gen_range(fixed!(0)..=bond_amount);
            let open_vault_share_price = rng.gen_range(fixed!(0)..=state.vault_share_price());
            let actual = panic::catch_unwind(|| {
                state.calculate_short_proceeds(
                    bond_amount,
                    share_amount,
                    open_vault_share_price,
                    state.vault_share_price(),
                    state.vault_share_price(),
                    state.flat_fee(),
                )
            });
            match chain
                .mock_hyperdrive_math()
                .calculate_short_proceeds_down(
                    bond_amount.into(),
                    share_amount.into(),
                    open_vault_share_price.into(),
                    state.vault_share_price().into(),
                    state.vault_share_price().into(),
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
    async fn fuzz_calculate_close_short_flat_plus_curve() -> Result<()> {
        let chain = TestChain::new().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let in_ = rng.gen_range(fixed!(0)..=state.bond_reserves());
            let maturity_time = state.position_duration();
            let current_time = rng.gen_range(fixed!(0)..=maturity_time);
            let actual = panic::catch_unwind(|| {
                state.calculate_close_short_flat_plus_curve(
                    in_,
                    maturity_time.into(),
                    current_time.into(),
                )
            });

            let normalized_time_remaining = state
                .calculate_normalized_time_remaining(maturity_time.into(), current_time.into());
            match chain
                .mock_hyperdrive_math()
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

    // Tests close short with an amount smaller than the minimum.
    #[tokio::test]
    async fn test_close_short_min_txn_amount() -> Result<()> {
        let mut rng = thread_rng();
        let state = rng.gen::<State>();
        let result = std::panic::catch_unwind(|| {
            state.calculate_close_short(
                (state.config.minimum_transaction_amount - 10).into(),
                state.calculate_spot_price(),
                state.vault_share_price(),
                0.into(),
                0.into(),
            )
        });
        assert!(result.is_err());
        Ok(())
    }
}
