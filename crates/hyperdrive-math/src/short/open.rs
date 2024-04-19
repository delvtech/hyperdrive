use ethers::types::I256;
use eyre::{eyre, Result};
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

use crate::{calculate_rate_given_fixed_price, State, YieldSpace};

impl State {
    /// Calculates the amount of base the trader will need to deposit for a short of
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
    pub fn calculate_open_short(
        &self,
        bond_amount: FixedPoint,
        mut open_vault_share_price: FixedPoint,
    ) -> Result<FixedPoint> {
        if bond_amount < self.config.minimum_transaction_amount.into() {
            return Err(eyre!("MinimumTransactionAmount: Input amount too low",));
        }

        // If the open share price hasn't been set, we use the current share
        // price, since this is what will be set as the checkpoint share price
        // in the next transaction.
        if open_vault_share_price == fixed!(0) {
            open_vault_share_price = self.vault_share_price();
        }

        let share_reserves_delta_in_base = self
            .vault_share_price()
            .mul_up(self.calculate_short_principal(bond_amount)?);
        // If the base proceeds of selling the bonds is greater than the bond
        // amount, then the trade occurred in the negative interest domain. We
        // revert in these pathological cases.
        if share_reserves_delta_in_base > bond_amount {
            return Err(eyre!("InsufficientLiquidity: Negative Interest",));
        }

        // NOTE: The order of additions and subtractions is important to avoid underflows.
        let spot_price = self.calculate_spot_price();
        Ok(
            bond_amount.mul_div_down(self.vault_share_price(), open_vault_share_price)
                + self.flat_fee() * bond_amount
                + self.curve_fee() * (fixed!(1e18) - spot_price) * bond_amount
                - share_reserves_delta_in_base,
        )
    }

    /// Calculates the spot price after opening a Hyperdrive short.
    pub fn calculate_spot_price_after_short(
        &self,
        bond_amount: FixedPoint,
        maybe_base_amount: Option<FixedPoint>,
    ) -> Result<FixedPoint> {
        let shares_amount = match maybe_base_amount {
            Some(base_amount) => base_amount / self.vault_share_price(),
            None => {
                let spot_price = self.calculate_spot_price();
                self.calculate_shares_out_given_bonds_in_down(bond_amount)
                    - self.open_short_curve_fee(bond_amount, spot_price)
                    + self.open_short_governance_fee(bond_amount, spot_price)
            }
        };
        let mut state: State = self.clone();
        state.info.bond_reserves += bond_amount.into();
        state.info.share_reserves -= shares_amount.into();
        Ok(state.calculate_spot_price())
    }

    /// Calculate the spot rate after a short has been opened.
    /// If a base_amount is not provided, then one is estimated using `calculate_open_short`.
    ///
    /// We calculate the rate for a fixed length of time as:
    /// $$
    /// r(y) = (1 - p(y)) / (p(y) t)
    /// $$
    ///
    /// where $p(y)$ is the spot price after a short for `delta_bonds`$= y$ and
    /// t is the normalized position druation.
    ///
    /// In this case, we use the resulting spot price after a hypothetical short
    /// for `bond_amount` is opened.
    pub fn calculate_spot_rate_after_short(
        &self,
        bond_amount: FixedPoint,
        maybe_base_amount: Option<FixedPoint>,
    ) -> Result<FixedPoint> {
        let price = self.calculate_spot_price_after_short(bond_amount, maybe_base_amount)?;
        Ok(calculate_rate_given_fixed_price(
            price,
            self.position_duration(),
        ))
    }

    /// Calculate the implied rate of opening a short at a given size. This rate
    /// is calculated as an APY.
    ///
    /// Given the effective fixed rate the short will pay $r_{effective}$ and
    /// the variable rate the short will receive $r_{variable}$, the short's
    /// implied APY, $r_{implied}$ will be:
    ///
    /// $$
    /// r_{implied} = \frac{r_{variable} - r_{effective}}{r_{effective}}
    /// $$
    ///
    /// We can short-cut this calculation using the amount of base the short
    /// will pay and comparing this to the amount of base the short will receive
    /// if the variable rate stays the same. The implied rate is just the ROI
    /// if the variable rate stays the same.
    pub fn calculate_implied_rate(
        &self,
        bond_amount: FixedPoint,
        open_vault_share_price: FixedPoint,
        variable_apy: FixedPoint,
    ) -> Result<I256> {
        let base_paid = self.calculate_open_short(
            bond_amount,
            self.calculate_spot_price(),
            open_vault_share_price,
        )?;
        let base_proceeds = bond_amount * variable_apy;
        if base_proceeds > base_paid {
            Ok(I256::try_from((base_proceeds - base_paid) / base_paid)?)
        } else {
            Ok(-I256::try_from((base_paid - base_proceeds) / base_paid)?)
        }
    }

    /// Calculates the amount of short principal that the LPs need to pay to back a
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
    pub fn calculate_short_principal(&self, bond_amount: FixedPoint) -> Result<FixedPoint> {
        self.calculate_shares_out_given_bonds_in_down_safe(bond_amount)
    }

    /// Calculates the derivative of the short principal $P(x)$ w.r.t. the amount of
    /// bonds that are shorted $x$.
    ///
    /// The derivative is calculated as:
    ///
    /// $$
    /// P'(x) = \tfrac{1}{c} \cdot (y + x)^{-t_s} \cdot \left(
    ///             \tfrac{\mu}{c} \cdot (k - (y + x)^{1 - t_s})
    ///         \right)^{\tfrac{t_s}{1 - t_s}}
    /// $$
    pub fn calculate_short_principal_derivative(&self, bond_amount: FixedPoint) -> FixedPoint {
        let lhs = fixed!(1e18)
            / (self
                .vault_share_price()
                .mul_up((self.bond_reserves() + bond_amount).pow(self.time_stretch())));
        let rhs = ((self.initial_vault_share_price() / self.vault_share_price())
            * (self.k_down()
                - (self.bond_reserves() + bond_amount).pow(fixed!(1e18) - self.time_stretch())))
        .pow(
            self.time_stretch()
                .div_up(fixed!(1e18) - self.time_stretch()),
        );
        lhs * rhs
    }
}

#[cfg(test)]
mod tests {
    use std::panic;

    use ethers::types::{I256, U256};
    use fixed_point_macros::{fixed, int256};
    use hyperdrive_wrappers::wrappers::mock_erc4626::MockERC4626;
    use rand::{thread_rng, Rng};
    use test_utils::{
        chain::TestChain,
        constants::{BOB, FAST_FUZZ_RUNS, FUZZ_RUNS},
    };

    use super::*;

    #[tokio::test]
    async fn test_short_principal() -> Result<()> {
        // This test is the same as the yield_space.rs `fuzz_calculate_max_buy_shares_in_safe`,
        // but is worth having around in case we ever change how we compute short principal.
        let chain = TestChain::new().await?;
        let mut rng = thread_rng();
        let state = rng.gen::<State>();
        let bond_amount = rng.gen_range(fixed!(10e18)..=fixed!(10_000_000e18));
        let actual = state.calculate_short_principal(bond_amount);
        match chain
            .mock_yield_space_math()
            .calculate_shares_out_given_bonds_in_down_safe(
                state.effective_share_reserves().into(),
                state.bond_reserves().into(),
                bond_amount.into(),
                (fixed!(1e18) - state.time_stretch()).into(),
                state.vault_share_price().into(),
                state.initial_vault_share_price().into(),
            )
            .call()
            .await
        {
            Ok((expected, expected_status)) => {
                assert_eq!(actual.is_ok(), expected_status);
                assert_eq!(actual.unwrap_or(fixed!(0)), expected.into());
            }
            Err(_) => assert!(actual.is_err()),
        }
        Ok(())
    }

    /// This test empirically tests `short_principal_derivative` by calling
    /// `short_principal` at two points and comparing the empirical result
    /// with the output of `short_principal_derivative`.
    #[tokio::test]
    async fn fuzz_short_principal_derivative() -> Result<()> {
        let mut rng = thread_rng();
        // We use a relatively large epsilon here due to the underlying fixed point pow
        // function not being monotonically increasing.
        let empirical_derivative_epsilon = fixed!(1e12);
        // TODO pretty big comparison epsilon here
        let test_comparison_epsilon = fixed!(1e16);

        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let amount = rng.gen_range(fixed!(10e18)..=fixed!(10_000_000e18));

            let p1_result = state.calculate_short_principal(amount - empirical_derivative_epsilon);
            let p1;
            let p2;
            match p1_result {
                // If the amount results in the pool being insolvent, skip this iteration
                Ok(p) => p1 = p,
                Err(_) => continue,
            }

            let p2_result = state.calculate_short_principal(amount + empirical_derivative_epsilon);
            match p2_result {
                // If the amount results in the pool being insolvent, skip this iteration
                Ok(p) => p2 = p,
                Err(_) => continue,
            }
            // Sanity check
            assert!(p2 > p1);

            let empirical_derivative = (p2 - p1) / (fixed!(2e18) * empirical_derivative_epsilon);
            let short_deposit_derivative = state.calculate_short_principal_derivative(amount);

            let derivative_diff;
            if short_deposit_derivative >= empirical_derivative {
                derivative_diff = short_deposit_derivative - empirical_derivative;
            } else {
                derivative_diff = empirical_derivative - short_deposit_derivative;
            }
            assert!(
                derivative_diff < test_comparison_epsilon,
                "expected (derivative_diff={}) < (test_comparison_epsilon={}), \
                calculated_derivative={}, emperical_derivative={}",
                derivative_diff,
                test_comparison_epsilon,
                short_deposit_derivative,
                empirical_derivative
            );
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_calculate_spot_price_after_short() -> Result<()> {
        // Spawn a test chain and create two agents -- Alice and Bob. Alice is
        // funded with a large amount of capital so that she can initialize the
        // pool. Bob is funded with a small amount of capital so that we can
        // test opening a short and verify that the ending spot price is what we
        // expect.
        let mut rng = thread_rng();
        let chain = TestChain::new().await?;
        let mut alice = chain.alice().await?;
        let mut bob = chain.bob().await?;

        for _ in 0..*FUZZ_RUNS {
            // Snapshot the chain.
            let id = chain.snapshot().await?;

            // Fund Alice and Bob.
            let fixed_rate = rng.gen_range(fixed!(0.01e18)..=fixed!(0.1e18));
            let contribution = rng.gen_range(fixed!(10_000e18)..=fixed!(500_000_000e18));
            let budget = rng.gen_range(fixed!(10e18)..=fixed!(500_000_000e18));
            alice.fund(contribution).await?;
            bob.fund(budget).await?;

            // Alice initializes the pool.
            alice.initialize(fixed_rate, contribution, None).await?;

            // Attempt to predict the spot price after opening a short.
            let bond_amount = rng.gen_range(fixed!(0.01e18)..=bob.calculate_max_short(None).await?);
            let current_state = bob.get_state().await?;
            let expected_spot_price =
                current_state.calculate_spot_price_after_short(bond_amount, None)?;

            // Open the short.
            bob.open_short(bond_amount, None, None).await?;

            // Verify that the predicted spot price is equal to the ending spot
            // price. These won't be exactly equal because the vault share price
            // increases between the prediction and opening the short.
            let actual_spot_price = bob.get_state().await?.calculate_spot_price();
            let delta = if actual_spot_price > expected_spot_price {
                actual_spot_price - expected_spot_price
            } else {
                expected_spot_price - actual_spot_price
            };
            // TODO: Why can't this pass with a tolerance of 1e9?
            let tolerance = fixed!(1e11);

            assert!(
                delta < tolerance,
                "expected: delta = {} < {} = tolerance",
                delta,
                tolerance
            );

            // Revert to the snapshot and reset the agent's wallets.
            chain.revert(id).await?;
            alice.reset(Default::default());
            bob.reset(Default::default());
        }

        Ok(())
    }

    #[tokio::test]
    async fn test_calculate_implied_rate() -> Result<()> {
        // Spwan a test chain with two agents.
        let mut rng = thread_rng();
        let chain = TestChain::new().await?;
        let mut alice = chain.alice().await?;
        let mut bob = chain.bob().await?;

        for _ in 0..*FUZZ_RUNS {
            // Snapshot the chain.
            let id = chain.snapshot().await?;

            // Fund Alice and Bob.
            let fixed_rate = rng.gen_range(fixed!(0.01e18)..=fixed!(0.1e18));
            let contribution = rng.gen_range(fixed!(100_000e18)..=fixed!(100_000_000e18));
            let budget = fixed!(100_000_000e18);
            alice.fund(contribution).await?;
            bob.fund(budget).await?;

            // Set a random variable rate.
            let variable_rate = rng.gen_range(fixed!(0.01e18)..=fixed!(1e18));
            let vault = MockERC4626::new(
                bob.get_config().vault_shares_token,
                chain.chain().client(BOB.clone()).await?,
            );
            vault.set_rate(variable_rate.into()).send().await?;

            // Alice initializes the pool.
            alice.initialize(fixed_rate, contribution, None).await?;

            // Bob opens a short with a random bond amount. Before opening the
            // short, we calculate the implied rate.
            let bond_amount = rng.gen_range(fixed!(1e18)..=contribution);
            let implied_rate = bob.get_state().await?.calculate_implied_rate(
                bond_amount,
                bob.get_state().await?.vault_share_price(),
                variable_rate.into(),
            )?;
            let (maturity_time, base_paid) = bob.open_short(bond_amount, None, None).await?;

            // The term passes and interest accrues.
            chain
                .increase_time(bob.get_config().position_duration.low_u128())
                .await?;

            // Bob closes his short.
            let base_proceeds = bob.close_short(maturity_time, bond_amount, None).await?;

            // Ensure that the implied rate matches the realized rate from
            // holding the short to maturity.
            let realized_rate = if base_proceeds > base_paid {
                I256::try_from((base_proceeds - base_paid) / base_paid)?
            } else {
                -I256::try_from((base_paid - base_proceeds) / base_paid)?
            };
            let error = (implied_rate - realized_rate).abs();
            let tolerance = int256!(1e14);
            assert!(
                error < tolerance,
                "error {:?} exceeds tolerance of {}",
                error,
                tolerance
            );

            // Revert to the snapshot and reset the agent's wallets.
            chain.revert(id).await?;
            alice.reset(Default::default());
            bob.reset(Default::default());
        }

        Ok(())
    }

    // Tests open short with an amount smaller than the minimum.
    #[tokio::test]
    async fn test_error_open_short_min_txn_amount() -> Result<()> {
        let mut rng = thread_rng();
        let state = rng.gen::<State>();
        let result = state.calculate_open_short(
            (state.config.minimum_transaction_amount - 10).into(),
            state.vault_share_price(),
        );
        assert!(result.is_err());
        Ok(())
    }

    // Tests open short with an amount larger than the maximum.
    #[tokio::test]
    async fn test_error_open_short_max_txn_amount() -> Result<()> {
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let checkpoint_exposure = {
                let value = rng.gen_range(fixed!(0)..=fixed!(10_000_000e18));
                if rng.gen() {
                    -I256::try_from(value).unwrap()
                } else {
                    I256::try_from(value).unwrap()
                }
            };
            let max_iterations = 7;
            let open_vault_share_price = rng.gen_range(fixed!(0)..=state.vault_share_price());
            let max_trade = panic::catch_unwind(|| {
                state.calculate_max_short(
                    U256::MAX,
                    open_vault_share_price,
                    checkpoint_exposure,
                    None,
                    Some(max_iterations),
                )
            });
            // Since we're fuzzing it's possible that the max can fail.
            // We're only going to use it in this test if it succeeded.
            match max_trade {
                Ok(max_trade) => {
                    // TODO: You should be able to add a small amount (e.g. 1e18) to max to fail.
                    // calc_open_short must be incorrect for the additional amount to have to be so large.
                    let result = state.calculate_open_short(
                        (max_trade + fixed!(100_000_000e18)).into(),
                        state.vault_share_price(),
                    );
                    match result {
                        Ok(_) => panic!("calculate_open_short should have failed but succeeded."),
                        Err(_) => continue,
                    }
                }
                Err(_) => continue,
            }
        }

        Ok(())
    }

    // TODO ideally we would add a solidity fuzz test that tests `calculate_open_short` against
    // opening longs in solidity, where we attempt to trade outside of expected values (so that
    // we can also test error parities as well). However, the current test chain only exposes
    // the underlying hyperdrive math functions, which doesn't take into account fees and negative
    // interest checks.
    // https://github.com/delvtech/hyperdrive/issues/937
}
