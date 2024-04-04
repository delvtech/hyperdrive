use eyre::Result;
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

use crate::{State, YieldSpace};

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
        short_amount: FixedPoint,
        spot_price: FixedPoint,
        mut open_vault_share_price: FixedPoint,
    ) -> Result<FixedPoint> {
        if short_amount < self.config.minimum_transaction_amount.into() {
            // TODO would be nice to return a `Result` here instead of a panic.
            panic!("MinimumTransactionAmount: Input amount too low");
        }

        // If the open share price hasn't been set, we use the current share
        // price, since this is what will be set as the checkpoint share price
        // in the next transaction.
        if open_vault_share_price == fixed!(0) {
            open_vault_share_price = self.vault_share_price();
        }

        let share_reserves_delta_in_base = self
            .vault_share_price()
            .mul_up(self.short_principal(short_amount)?);
        // If the base proceeds of selling the bonds is greater than the bond
        // amount, then the trade occurred in the negative interest domain. We
        // revert in these pathological cases.
        if share_reserves_delta_in_base > short_amount {
            // TODO would be nice to return a `Result` here instead of a panic.
            panic!("InsufficientLiquidity: Negative Interest");
        }

        // NOTE: The order of additions and subtractions is important to avoid underflows.
        Ok(
            short_amount.mul_div_down(self.vault_share_price(), open_vault_share_price)
                + self.flat_fee() * short_amount
                + self.curve_fee() * (fixed!(1e18) - spot_price) * short_amount
                - share_reserves_delta_in_base,
        )
    }

    /// Calculates the spot price after opening a Hyperdrive short.
    pub fn calculate_spot_price_after_short(
        &self,
        bond_amount: FixedPoint,
        base_amount: Option<FixedPoint>,
    ) -> FixedPoint {
        let shares_amount = match base_amount {
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
        state.calculate_spot_price()
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
    pub fn short_principal(&self, short_amount: FixedPoint) -> Result<FixedPoint> {
        self.calculate_shares_out_given_bonds_in_down_safe(short_amount)
    }
}

#[cfg(test)]
mod tests {
    use fixed_point_macros::fixed;
    use rand::{thread_rng, Rng};
    use test_utils::{
        agent::Agent,
        chain::{Chain, TestChain},
        constants::FUZZ_RUNS,
    };

    use super::*;

    #[tokio::test]
    async fn fuzz_calculate_spot_price_after_short() -> Result<()> {
        // Spawn a test chain and create two agents -- Alice and Bob. Alice is
        // funded with a large amount of capital so that she can initialize the
        // pool. Bob is funded with a small amount of capital so that we can
        // test opening a short and verify that the ending spot price is what we
        // expect.
        let mut rng = thread_rng();
        let chain = TestChain::new(2).await?;
        let (alice, bob) = (chain.accounts()[0].clone(), chain.accounts()[1].clone());
        let mut alice =
            Agent::new(chain.client(alice).await?, chain.addresses().clone(), None).await?;
        let mut bob = Agent::new(chain.client(bob).await?, chain.addresses(), None).await?;

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
            let short_amount =
                rng.gen_range(fixed!(0.01e18)..=bob.calculate_max_short(None).await?);
            let current_state = bob.get_state().await?;
            let expected_spot_price =
                current_state.calculate_spot_price_after_short(short_amount, None);

            // Open the short.
            bob.open_short(short_amount, None, None).await?;

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

    // Tests open short with an amount smaller than the minimum.
    #[tokio::test]
    async fn test_error_open_short_min_txn_amount() -> Result<()> {
        let mut rng = thread_rng();
        let state = rng.gen::<State>();
        let result = std::panic::catch_unwind(|| {
            state.calculate_open_short(
                (state.config.minimum_transaction_amount - 10).into(),
                state.calculate_spot_price(),
                state.vault_share_price(),
            )
        });
        assert!(result.is_err());
        Ok(())
    }

    // TODO ideally we would test calculate open short with an amount larger than the maximum size.
    // However, `calculate_max_short` requires a `checkpoint_exposure`` argument, which requires
    // implementing checkpointing in the rust sdk.
    // https://github.com/delvtech/hyperdrive/issues/862

    // TODO ideally we would add a solidity fuzz test that tests `calculate_open_short` against
    // opening longs in solidity, where we attempt to trade outside of expected values (so that
    // we can also test error parities as well). However, the current test chain only exposes
    // the underlying hyperdrive math functions, which doesn't take into account fees and negative
    // interest checks.
    // https://github.com/delvtech/hyperdrive/issues/937
}
