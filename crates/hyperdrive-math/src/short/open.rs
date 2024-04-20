use ethers::types::I256;
use eyre::{eyre, Result};
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

use crate::{calculate_rate_given_fixed_price, State, YieldSpace};

impl State {
    /// Calculates the amount of base the trader will need to deposit for a short of
    /// a given size.
    ///
    /// For some number of bonds being shorted, $\Delta y$, the short deposit is made up of several components:
    /// - The short principal: $P_{\text{lp}}(\Delta y)$
    /// - The curve fee: $\Phi_{c}(\Delta y) = \phi_{c} \cdot ( 1 - p_{0} ) \cdot \Delta y
    /// - The flat fee: $\Phi_{f}(\Delta y) = \tfrac{1}{c} ( \Delta y \cdot (1 - t) \cdot \phi_{f} )
    /// - The total value in shares that underlies the bonds: $\tfrac{c_1}{c_0 \cdot c} \Delta y$
    ///
    /// The short principal is given by:
    ///
    /// $$
    /// P_{\text{lp}}(\Delta y) = z - \tfrac{1}{\mu}
    ///   \cdot (\tfrac{\mu}{c} \cdot (k - (y + \Delta y)^{1 - t_s}))^{\tfrac{1}{1 - t_s}}
    /// $$
    ///
    /// The short proceeds is given by
    ///
    /// $$
    /// P_{\text{short}}(\Delta y) = \tfrac{\Delta y \cdot c_{1}}{c_{0} \cdot c}
    ///   + \tfrac{\Delta y}{c} \cdot \Phi_{f}(\Delta y)
    /// $$
    ///
    /// And finally the short deposit in base is:
    ///
    /// $$
    ///     D(\Delta y)=
    /// \begin{cases}
    ///     c \cdot \left( P_{\text{short}}(\Delta y) - P_{\text{lp}}(\Delta y)
    ///       + \Phi_{c}(\Delta y) \right),
    ///       & \text{if } P_{\text{short}} > P_{\text{lp}}(\Delta y) - \Phi_{c}(\Delta y) \\
    ///     0,              & \text{otherwise}
    /// \end{cases}
    /// $$
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

        let share_reserves_delta = self.calculate_short_principal(bond_amount)?;
        // If the base proceeds of selling the bonds is greater than the bond
        // amount, then the trade occurred in the negative interest domain. We
        // revert in these pathological cases.
        if share_reserves_delta.mul_up(self.vault_share_price()) > bond_amount {
            return Err(eyre!("InsufficientLiquidity: Negative Interest",));
        }

        // NOTE: Round up to overestimate the base deposit.
        //
        // The trader will need to deposit capital to pay for the fixed rate,
        // the curve fee, the flat fee, and any back-paid interest that will be
        // received back upon closing the trade. If negative interest has
        // accrued during the current checkpoint, we set the close vault share
        // price to equal the open vault share price. This ensures that shorts
        // don't benefit from negative interest that accrued during the current
        // checkpoint.
        let spot_price = self.calculate_spot_price();
        let curve_fee = self.open_short_curve_fee(bond_amount, spot_price);
        // Use the position duraiton as the current time and maturity time to simulate closing at maturity.
        let flat_fee = self.close_short_flat_fee(
            bond_amount,
            self.position_duration().into(),
            self.position_duration().into(),
        );

        // Now we can calculate the proceeds in a way that adjusts for the backdated vault price.
        // $$
        // \text{base_proceeds} = (
        //    \frac{c1 \cdot \Delta y}{c0 \cdot c}
        //    + \frac{\Delta y \cdot \phi_f}{c} - \Delta z
        // ) \cdot c
        // $$
        let base_deposit = self
            .calculate_short_proceeds_up(
                bond_amount,
                share_reserves_delta - curve_fee,
                open_vault_share_price,
                self.vault_share_price().max(open_vault_share_price),
                self.vault_share_price(),
                flat_fee,
            )
            .mul_up(self.vault_share_price());

        Ok(base_deposit)
    }

    /// Calculates the derivative of the short deposit function with respect to the
    /// short amount. This allows us to use Newton's method to approximate the
    /// maximum short that a trader can open.
    ///
    /// Using this, calculating $D'(\Delta y)$ is straightforward:
    ///
    /// $$
    /// D'(\Delta y) = c \cdot (
    ///   P^{\prime}_{\text{short}}(\Delta y)
    ///   - P^{\prime}_{\text{lp}}(\Delta y)
    ///   + \Phi^{\prime}_{c}(\Delta y)
    /// )
    /// $$
    pub fn short_deposit_derivative(
        &self,
        bond_amount: FixedPoint,
        spot_price: FixedPoint,
        open_vault_share_price: FixedPoint,
        close_vault_share_price: FixedPoint,
        vault_share_price: FixedPoint,
    ) -> Result<FixedPoint> {
        let flat_fee = self.close_short_flat_fee(
            bond_amount,
            self.position_duration().into(),
            self.position_duration().into(),
        );

        // Short circuit the derivative if the forward function returns 0.
        if self.calculate_short_proceeds_up(
            bond_amount,
            self.calculate_short_principal(bond_amount)?
                - self.open_short_curve_fee(bond_amount, spot_price),
            open_vault_share_price,
            close_vault_share_price,
            vault_share_price,
            flat_fee,
        ) == fixed!(0)
        {
            return Ok(fixed!(0));
        }

        // Flat fee derivative = (1 - t) * phi_f / c
        // Since t=0 when closing at maturity we can use phi_f / c
        let flat_fee_derivative = self.flat_fee() / vault_share_price;
        let curve_fee_derivative = self.curve_fee() * (fixed!(1e18) - spot_price);
        let short_principal_derivative = self.calculate_short_principal_derivative(bond_amount);
        let short_proceeds_derivative = self.calculate_short_proceeds_derivative(
            bond_amount,
            open_vault_share_price,
            close_vault_share_price,
            vault_share_price,
            flat_fee,
            flat_fee_derivative,
        );

        Ok(vault_share_price
            * (short_proceeds_derivative - short_principal_derivative + curve_fee_derivative))
    }

    /// Calculates the proceeds in shares of closing a short position. This
    /// takes into account the trading profits, the interest that was
    /// earned by the short, the flat fee the short pays, and the amount of
    /// margin that was released by closing the short. The math for the
    /// short's proceeds in base is given by:
    ///
    /// $$
    /// proceeds = (\frac{c1}{c_0} + \text{flat_fee}) \cdot \frac{\Delta y}{c} - dz
    /// $$
    ///
    /// We convert the proceeds to shares by dividing by the current vault
    /// share price. In the event that the interest is negative and
    /// outweighs the trading profits and margin released, the short's
    /// proceeds are marked to zero.
    fn calculate_short_proceeds_up(
        &self,
        bond_amount: FixedPoint,
        share_amount: FixedPoint,
        open_vault_share_price: FixedPoint,
        close_vault_share_price: FixedPoint,
        vault_share_price: FixedPoint,
        flat_fee: FixedPoint,
    ) -> FixedPoint {
        // NOTE: Round up to overestimate the short proceeds.
        //
        // The total value is the amount of shares that underlies the bonds that
        // were shorted. The bonds start by being backed 1:1 with base, and the
        // total value takes into account all of the interest that has accrued
        // since the short was opened.
        //
        // total_value = (c1 / (c0 * c)) * dy
        let mut total_value = bond_amount
            .mul_div_up(close_vault_share_price, open_vault_share_price)
            .div_up(vault_share_price);

        // NOTE: Round up to overestimate the short proceeds.
        //
        // We increase the total value by the flat fee amount, because it is
        // included in the total amount of capital underlying the short.
        total_value += bond_amount.mul_div_up(flat_fee, vault_share_price);

        // If the interest is more negative than the trading profits and margin
        // released, then the short proceeds are marked to zero. Otherwise, we
        // calculate the proceeds as the sum of the trading proceeds, the
        // interest proceeds, and the margin released.
        if total_value > share_amount {
            total_value - share_amount
        } else {
            fixed!(0)
        }
    }

    /// Returns the derivative of the short proceeds calculation, assuming that the interest is
    /// less negative than the trading profits and margin released.
    ///
    /// $$
    /// P^{\prime}_{\text{short}}(\Delta y) = \tfrac{c_{1}}{c_{0} \cdot c}
    /// + \tfrac{\Phi_{f}(\Delta y)}{c}
    /// + \tfrac{\Delta y \cdot \Phi^{\prime}_{f}(\Delta y)}{c}
    /// $$
    pub fn calculate_short_proceeds_derivative(
        &self,
        bond_amount: FixedPoint,
        open_vault_share_price: FixedPoint,
        close_vault_share_price: FixedPoint,
        vault_share_price: FixedPoint,
        flat_fee: FixedPoint,
        flat_fee_derivative: FixedPoint,
    ) -> FixedPoint {
        close_vault_share_price / (open_vault_share_price * vault_share_price)
            + flat_fee / vault_share_price
            + bond_amount * flat_fee_derivative / vault_share_price
    }

    /// Calculates the amount of short principal that the LPs need to pay to back a
    /// short before fees are taken into consideration, $P(x)$.
    ///
    /// Let the LP principal that backs $x$ shorts be given by $P(x)$. We can
    /// solve for this in terms of $x$ using the YieldSpace invariant:
    ///
    /// $$
    /// k = \tfrac{c}{\mu} \cdot (\mu \cdot (z - P(\Delta y)))^{1 - t_s} + (y + \Delta y)^{1 - t_s} \\
    /// \implies \\
    /// P_{\text{lp}}(\Delta y) = z - \tfrac{1}{\mu} \cdot (
    ///   \tfrac{\mu}{c}
    ///   \cdot (k - (y + \Delta y)^{1 - t_s})
    /// )^{\tfrac{1}{1 - t_s}}
    /// $$
    pub fn calculate_short_principal(&self, bond_amount: FixedPoint) -> Result<FixedPoint> {
        self.calculate_shares_out_given_bonds_in_down_safe(bond_amount)
    }

    /// Calculates the derivative of the short principal $P_{\text{lp}}(\Delta y)$
    /// w.r.t. the amount of bonds that are shorted $\Delta y$.
    ///
    /// The derivative is calculated as:
    ///
    /// $$
    /// P^{\prime}_{\text{lp}}(\Delta y) = \tfrac{1}{c} \cdot (y + \Delta y)^{-t_s} \cdot \left(
    ///     \tfrac{\mu}{c} \cdot (k - (y + \Delta y)^{1 - t_s})
    ///   \right)^{\tfrac{t_s}{1 - t_s}}
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

    /// Calculates the spot price after opening a short.
    pub fn calculate_spot_price_after_short(
        &self,
        bond_amount: FixedPoint,
        maybe_base_amount: Option<FixedPoint>,
    ) -> Result<FixedPoint> {
        let shares_amount = match maybe_base_amount {
            Some(base_amount) => base_amount / self.vault_share_price(),
            None => self.calculate_open_short(bond_amount, self.vault_share_price())?,
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
        let base_paid = self.calculate_open_short(bond_amount, open_vault_share_price)?;
        let base_proceeds = bond_amount * variable_apy;
        if base_proceeds > base_paid {
            Ok(I256::try_from((base_proceeds - base_paid) / base_paid)?)
        } else {
            Ok(-I256::try_from((base_paid - base_proceeds) / base_paid)?)
        }
    }
}

#[cfg(test)]
mod tests {
    use std::panic;

    use ethers::{signers::LocalWallet, types::U256};
    use fixed_point_macros::{fixed, int256, uint256};
    use hyperdrive_wrappers::wrappers::{
        ihyperdrive::{Checkpoint, Options},
        mock_erc4626::MockERC4626,
    };
    use rand::{thread_rng, Rng, SeedableRng};
    use rand_chacha::ChaCha8Rng;
    use test_utils::{
        agent::Agent,
        chain::{ChainClient, TestChain},
        constants::{BOB, FAST_FUZZ_RUNS, FUZZ_RUNS},
    };
    use tracing_test::traced_test;

    use super::*;

    /// Executes random trades throughout a Hyperdrive term.
    async fn preamble(
        rng: &mut ChaCha8Rng,
        alice: &mut Agent<ChainClient<LocalWallet>, ChaCha8Rng>,
        bob: &mut Agent<ChainClient<LocalWallet>, ChaCha8Rng>,
        celine: &mut Agent<ChainClient<LocalWallet>, ChaCha8Rng>,
        fixed_rate: FixedPoint,
    ) -> Result<()> {
        // Fund the agent accounts and initialize the pool.
        alice
            .fund(rng.gen_range(fixed!(1_000e18)..=fixed!(500_000_000e18)))
            .await?;
        bob.fund(rng.gen_range(fixed!(1_000e18)..=fixed!(500_000_000e18)))
            .await?;
        celine
            .fund(rng.gen_range(fixed!(1_000e18)..=fixed!(500_000_000e18)))
            .await?;

        // Alice initializes the pool.
        alice.initialize(fixed_rate, alice.base(), None).await?;

        // Advance the time for over a term and make trades in some of the checkpoints.
        let mut time_remaining = alice.get_config().position_duration;
        while time_remaining > uint256!(0) {
            // Bob opens a long.
            let discount = rng.gen_range(fixed!(0.1e18)..=fixed!(0.5e18));
            let long_amount =
                rng.gen_range(fixed!(1e12)..=bob.calculate_max_long(None).await? * discount);
            bob.open_long(long_amount, None, None).await?;

            // Celine opens a short.
            let discount = rng.gen_range(fixed!(0.1e18)..=fixed!(0.5e18));
            let short_amount =
                rng.gen_range(fixed!(1e12)..=celine.calculate_max_short(None).await? * discount);
            celine.open_short(short_amount, None, None).await?;

            // Advance the time and mint all of the intermediate checkpoints.
            let multiplier = rng.gen_range(fixed!(5e18)..=fixed!(50e18));
            let delta = FixedPoint::from(time_remaining)
                .min(FixedPoint::from(alice.get_config().checkpoint_duration) * multiplier);
            time_remaining -= U256::from(delta);
            alice
                .advance_time(
                    fixed!(0), // TODO: Use a real rate.
                    delta,
                )
                .await?;
        }

        // Mint a checkpoint to close any matured positions from the first checkpoint
        // of trading.
        alice
            .checkpoint(alice.latest_checkpoint().await?, uint256!(0), None)
            .await?;

        Ok(())
    }

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

    /// This test empirically tests `short_deposit_derivative` by calling
    /// `calculate_open_short` at two points and comparing the empirical result
    /// with the output of `short_deposit_derivative`.
    #[traced_test]
    #[tokio::test]
    async fn fuzz_short_deposit_derivative() -> Result<()> {
        let mut rng = thread_rng();
        // We use a relatively large epsilon here due to the underlying fixed point pow
        // function not being monotonically increasing.
        let empirical_derivative_epsilon = fixed!(1e12);
        // TODO pretty big comparison epsilon here
        let test_comparison_epsilon = fixed!(1e15);

        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let amount = rng.gen_range(fixed!(10e18)..=fixed!(10_000_000e18));

            let p1_result = state.calculate_open_short(
                amount - empirical_derivative_epsilon,
                state.vault_share_price(),
            );
            let p1;
            let p2;
            match p1_result {
                // If the amount results in the pool being insolvent, skip this iteration
                Ok(p) => p1 = p,
                Err(_) => continue,
            }

            let p2_result = state.calculate_open_short(
                amount + empirical_derivative_epsilon,
                state.vault_share_price(),
            );
            match p2_result {
                // If the amount results in the pool being insolvent, skip this iteration
                Ok(p) => p2 = p,
                Err(_) => continue,
            }

            // Sanity check
            assert!(p2 > p1);

            // Compute the derivative.
            let empirical_derivative = (p2 - p1) / (fixed!(2e18) * empirical_derivative_epsilon);

            // Setting open, close, and current vault share price to be equal assumes 0% variable yield.
            let short_deposit_derivative = state.short_deposit_derivative(
                amount,
                state.calculate_spot_price(),
                state.vault_share_price(),
                state.vault_share_price(),
                state.vault_share_price(),
            )?;

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
    async fn fuzz_error_open_short_max_txn_amount() -> Result<()> {
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
            let max_trade = state.calculate_max_short(
                U256::MAX,
                open_vault_share_price,
                checkpoint_exposure,
                None,
                Some(max_iterations),
            );
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

    #[tokio::test]
    pub async fn fuzz_calc_open_short() -> Result<()> {
        // Set up a random number generator. We use ChaCha8Rng with a randomly
        // generated seed, which makes it easy to reproduce test failures given
        // the seed.
        let mut rng = {
            let mut rng = thread_rng();
            let seed = rng.gen();
            ChaCha8Rng::seed_from_u64(seed)
        };

        // Initialize the test chain.
        let chain = TestChain::new().await?;
        let mut alice = chain.alice().await?;
        let mut bob = chain.bob().await?;
        let mut celine = chain.celine().await?;

        for _ in 0..*FUZZ_RUNS {
            // Snapshot the chain.
            let id = chain.snapshot().await?;

            // Run the preamble.
            let fixed_rate = fixed!(0.05e18);
            preamble(&mut rng, &mut alice, &mut bob, &mut celine, fixed_rate).await?;

            // Get state and trade details.
            let state = alice.get_state().await?;
            let Checkpoint {
                vault_share_price: open_vault_share_price,
            } = alice
                .get_checkpoint(state.to_checkpoint(alice.now().await?))
                .await?;
            let slippage_tolerance = fixed!(0.001e18);
            let max_short = bob.calculate_max_short(Some(slippage_tolerance)).await?;
            let short_amount = rng
                .gen_range(FixedPoint::from(state.config.minimum_transaction_amount)..=max_short);

            // Compare the open short call output against calculate_open_short.
            let acutal_base_amount =
                state.calculate_open_short(short_amount, open_vault_share_price.into());

            match bob
                .hyperdrive()
                .open_short(
                    short_amount.into(),
                    FixedPoint::from(U256::MAX).into(),
                    fixed!(0).into(),
                    Options {
                        destination: bob.address(),
                        as_base: true,
                        extra_data: [].into(),
                    },
                )
                .call()
                .await
            {
                Ok((_, expected_base_amount)) => {
                    assert_eq!(acutal_base_amount.unwrap(), expected_base_amount.into());
                }
                Err(_) => assert!(acutal_base_amount.is_err()),
            }

            // Revert to the snapshot and reset the agent's wallets.
            chain.revert(id).await?;
            alice.reset(Default::default());
            bob.reset(Default::default());
            celine.reset(Default::default());
        }

        Ok(())
    }
}
