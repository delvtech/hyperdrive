use fixed_point::FixedPoint;

use crate::{calculate_rate_given_fixed_price, State, YieldSpace};

impl State {
    /// Calculates the long amount that will be opened for a given base amount.
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

        if base_amount < self.config.minimum_transaction_amount.into() {
            // TODO would be nice to return a `Result` here instead of a panic.
            panic!("MinimumTransactionAmount: Input amount too low");
        }

        let long_amount =
            self.calculate_bonds_out_given_shares_in_down(base_amount / self.vault_share_price());

        // Throw an error if opening the long would result in negative interest.
        let ending_spot_price =
            self.calculate_spot_price_after_long(base_amount, long_amount.into());
        let max_spot_price = self.calculate_max_spot_price();
        if ending_spot_price > max_spot_price {
            // TODO would be nice to return a `Result` here instead of a panic.
            panic!("InsufficientLiquidity: Negative Interest");
        }

        long_amount - self.open_long_curve_fees(base_amount)
    }

    /// Calculates the spot price after opening a Hyperdrive long.
    /// If a bond_amount is not provided, then one is estimated using `calculate_open_long`.
    pub fn calculate_spot_price_after_long(
        &self,
        base_amount: FixedPoint,
        bond_amount: Option<FixedPoint>,
    ) -> FixedPoint {
        let bond_amount = match bond_amount {
            Some(bond_amount) => bond_amount,
            None => self.calculate_open_long(base_amount),
        };
        let mut state: State = self.clone();
        state.info.bond_reserves -= bond_amount.into();
        state.info.share_reserves += (base_amount / state.vault_share_price()
            - self.open_long_governance_fee(base_amount) / state.vault_share_price())
        .into();
        state.calculate_spot_price()
    }

    /// Calculate the spot rate after a long has been opened.
    /// If a bond_amount is not provided, then one is estimated using `calculate_open_long`.
    pub fn calculate_spot_rate_after_long(
        &self,
        base_amount: FixedPoint,
        bond_amount: Option<FixedPoint>,
    ) -> FixedPoint {
        calculate_rate_given_fixed_price(
            self.calculate_spot_price_after_long(base_amount, bond_amount),
            self.position_duration(),
        )
    }
}

#[cfg(test)]
mod tests {
    use ethers::types::U256;
    use eyre::Result;
    use fixed_point_macros::fixed;
    use rand::{thread_rng, Rng};
    use test_utils::{
        agent::Agent,
        chain::{Chain, TestChain},
        constants::FUZZ_RUNS,
    };

    use super::*;

    #[tokio::test]
    async fn fuzz_calculate_spot_price_after_long() -> Result<()> {
        // Spawn a test chain and create two agents -- Alice and Bob. Alice
        // is funded with a large amount of capital so that she can initialize
        // the pool. Bob is funded with a small amount of capital so that we
        // can test opening a long and verify that the ending spot price is what
        // we expect.
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

            // Attempt to predict the spot price after opening a long.
            let base_paid = rng.gen_range(fixed!(0.1e18)..=bob.calculate_max_long(None).await?);
            let expected_spot_price = bob
                .get_state()
                .await?
                .calculate_spot_price_after_long(base_paid, None);

            // Open the long.
            bob.open_long(base_paid, None, None).await?;

            // Verify that the predicted spot price is equal to the ending spot
            // price. These won't be exactly equal because the vault share price
            // increases between the prediction and opening the long.
            let actual_spot_price = bob.get_state().await?.calculate_spot_price();
            let delta = if actual_spot_price > expected_spot_price {
                actual_spot_price - expected_spot_price
            } else {
                expected_spot_price - actual_spot_price
            };
            let tolerance = fixed!(1e9);
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

    // Tests open long with an amount smaller than the minimum.
    #[tokio::test]
    async fn test_open_long_min_txn_amount() -> Result<()> {
        let mut rng = thread_rng();
        let state = rng.gen::<State>();
        let result = std::panic::catch_unwind(|| {
            state.calculate_open_long(state.config.minimum_transaction_amount - 10)
        });
        assert!(result.is_err());
        Ok(())
    }

    // Tests open short with an amount larger than the maximum.
    #[tokio::test]
    async fn test_open_long_max_amount() -> Result<()> {
        let mut rng = thread_rng();
        let state = rng.gen::<State>();
        let max_long_amount = state.calculate_max_long(U256::MAX, 0, Some(7));
        let result =
            std::panic::catch_unwind(|| state.calculate_open_long(max_long_amount + fixed!(10e18)));
        assert!(result.is_err());
        Ok(())
    }
}
