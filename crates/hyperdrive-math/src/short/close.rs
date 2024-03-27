use ethers::types::U256;
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

use crate::{
    close_short_curve_fee, close_short_flat_fee,
    yield_space::calculate_shares_in_given_bonds_out_up_safe, State, YieldSpace,
};

fn calculate_close_short_flat_plus_curve<F: Into<FixedPoint>>(
    ze: FixedPoint,
    y: FixedPoint,
    c: FixedPoint,
    mu: FixedPoint,
    t: FixedPoint,
    bond_amount: F,
    normalized_time_remaining: F,
) -> FixedPoint {
    let bond_amount = bond_amount.into();
    let normalized_time_remaining = normalized_time_remaining.into();

    // NOTE: We overestimate the trader's share payment to avoid sandwiches.
    //
    // Calculate the flat part of the trade
    let flat = bond_amount.mul_div_up(fixed!(1e18) - normalized_time_remaining, c);

    // Calculate the curve part of the trade
    let curve = if normalized_time_remaining > fixed!(0) {
        // NOTE: Round the `shareCurveDelta` up to overestimate the share
        // payment.
        //
        let curve_bonds_in = bond_amount * normalized_time_remaining;
        calculate_shares_in_given_bonds_out_up_safe(ze, y, c, mu, t, curve_bonds_in).unwrap()
    } else {
        fixed!(0)
    };

    flat + curve
}

// Calculates the proceeds in shares of closing a short position.
fn calculate_short_proceeds(
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

/// Gets the amount of shares the trader will receive after fees for closing a short
pub fn calculate_close_short<F: Into<FixedPoint>>(
    ze: FixedPoint,
    y: FixedPoint,
    c: FixedPoint,
    mu: FixedPoint,
    t: FixedPoint,
    curve_fee: FixedPoint,
    flat_fee: FixedPoint,
    bond_amount: F,
    open_vault_share_price: F,
    close_vault_share_price: F,
    normalized_time_remaining: F,
) -> FixedPoint {
    let bond_amount = bond_amount.into();
    let open_vault_share_price = open_vault_share_price.into();
    let close_vault_share_price = close_vault_share_price.into();
    let normalized_time_remaining = normalized_time_remaining.into();

    // Calculate flat + curve and subtract the fees from the trade.
    let share_reserves_delta =
        calculate_close_short_flat_plus_curve(
            ze,
            y,
            c,
            mu,
            t,
            bond_amount,
            normalized_time_remaining,
        ) + close_short_curve_fee(
            ze,
            y,
            c,
            mu,
            t,
            curve_fee,
            bond_amount,
            normalized_time_remaining,
        ) + close_short_flat_fee(c, flat_fee, bond_amount, normalized_time_remaining);

    // Calculate the share proceeds owed to the short.
    calculate_short_proceeds(
        bond_amount,
        share_reserves_delta,
        open_vault_share_price,
        close_vault_share_price,
        c,
        flat_fee,
    )
}

impl State {
    #[allow(dead_code)]
    fn calculate_close_short_flat_plus_curve<F: Into<FixedPoint>>(
        &self,
        bond_amount: F,
        maturity_time: U256,
        current_time: U256,
    ) -> FixedPoint {
        let bond_amount = bond_amount.into();
        let normalized_time_remaining =
            self.calculate_normalized_time_remaining(maturity_time, current_time);

        // NOTE: We overestimate the trader's share payment to avoid sandwiches.
        //
        // Calculate the flat part of the trade
        let flat = bond_amount.mul_div_up(
            fixed!(1e18) - normalized_time_remaining,
            self.vault_share_price(),
        );

        // Calculate the curve part of the trade
        let curve = if normalized_time_remaining > fixed!(0) {
            // NOTE: Round the `shareCurveDelta` up to overestimate the share
            // payment.
            //
            let curve_bonds_in = bond_amount * normalized_time_remaining;
            self.calculate_shares_in_given_bonds_out_up_safe(curve_bonds_in)
                .unwrap()
        } else {
            fixed!(0)
        };

        flat + curve
    }

    // Calculates the proceeds in shares of closing a short position.
    #[allow(dead_code)]
    fn calculate_short_proceeds(
        &self,
        bond_amount: FixedPoint,
        share_amount: FixedPoint,
        open_vault_share_price: FixedPoint,
        close_vault_share_price: FixedPoint,
        vault_share_price: FixedPoint,
        flat_fee: FixedPoint,
    ) -> FixedPoint {
        calculate_short_proceeds(
            bond_amount,
            share_amount,
            open_vault_share_price,
            close_vault_share_price,
            vault_share_price,
            flat_fee,
        )
    }

    /// Gets the amount of shares the trader will receive after fees for closing a short
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

        // Calculate flat + curve and subtract the fees from the trade.
        let share_reserves_delta =
            self.calculate_close_short_flat_plus_curve(bond_amount, maturity_time, current_time)
                + self.close_short_curve_fee(bond_amount, maturity_time, current_time)
                + self.close_short_flat_fee(bond_amount, maturity_time, current_time);

        // Calculate the share proceeds owed to the short.
        self.calculate_short_proceeds(
            bond_amount,
            share_reserves_delta,
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
            match mock
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
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_hyperdrive_math();

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
