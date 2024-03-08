use ethers::{providers::maybe, types::I256};
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

use crate::{State, YieldSpace};

impl State {
    /// Gets a target long that can be opened given a budget to achieve a desired fixed rate.
    pub fn get_targeted_long<F: Into<FixedPoint>, I: Into<I256>>(
        &self,
        budget: F,
        target_rate: F,
        checkpoint_exposure: I,
        maybe_max_iterations: Option<usize>,
    ) -> FixedPoint {
        let budget = budget.into();
        let target_rate = target_rate.into();
        let checkpoint_exposure = checkpoint_exposure.into();

        // Estimate the long that achieves a target rate
        let (absolute_target_base_amount, absolute_target_bond_amount) =
            self.absolute_targeted_long(target_rate);
        // Get the maximum long that brings the spot price to 1.
        let max_base_amount = self.get_max_long(budget, checkpoint_exposure, maybe_max_iterations);
        // Ensure that the target is less than the max.
        let target_base_amount = absolute_target_base_amount.min(max_base_amount);
        // Verify solvency.
        if self
            .solvency_after_long(
                absolute_target_base_amount,
                absolute_target_bond_amount,
                checkpoint_exposure,
            )
            .is_some()
        {
            return target_base_amount.min(budget);
        } else {
            // TODO: Refine using an iterative method
            panic!("Initial guess in `get_targeted_long` is insolvent.");
        }
    }

    /// Calculates the long that should be opened to hit a target interest rate.
    /// This calculation does not take Hyperdrive's solvency constraints into account and shouldn't be used directly.
    fn absolute_targeted_long<F: Into<FixedPoint>>(
        &self,
        target_rate: F,
    ) -> (FixedPoint, FixedPoint) {
        //
        // TODO: Docstring
        //
        let target_rate = target_rate.into();
        let c_over_mu = self
            .vault_share_price()
            .div_up(self.initial_vault_share_price());
        let scaled_rate = (target_rate.mul_up(self.position_duration()) + fixed!(1e18))
            .pow(fixed!(1e18) / self.time_stretch());
        let inner = (self.k_down()
            / (c_over_mu + scaled_rate.pow(fixed!(1e18) - self.time_stretch())))
        .pow(fixed!(1e18) / (fixed!(1e18) - self.time_stretch()));
        let target_share_reserves = inner / self.initial_vault_share_price();

        // Now that we have the target share reserves, we can calculate the
        // target bond reserves using the formula:
        //
        // TODO: docstring
        //
        let target_bond_reserves = inner * scaled_rate;

        // The absolute max base amount is given by:
        //
        // absolute_target_base_amount = c * (z_t - z)
        let absolute_target_base_amount =
            (target_share_reserves - self.effective_share_reserves()) * self.vault_share_price();

        // The absolute max bond amount is given by:
        //
        // absolute_target_bond_amount = (y - y_t) - c(x)
        let absolute_target_bond_amount = (self.bond_reserves() - target_bond_reserves)
            - self.open_long_curve_fees(absolute_target_base_amount);

        (absolute_target_base_amount, absolute_target_bond_amount)
    }
}

#[cfg(test)]
mod tests {
    use eyre::Result;
    use rand::{thread_rng, Rng};
    use test_utils::{
        agent::Agent,
        chain::{Chain, TestChain},
        constants::FUZZ_RUNS,
    };
    use tracing_test::traced_test;

    use super::*;

    #[traced_test]
    #[tokio::test]
    async fn test_get_targeted_long() -> Result<()> {
        // Spawn a test chain and create three agents -- Alice, Bob, and Claire. Alice
        // is funded with a large amount of capital so that she can initialize
        // the pool. Bob is funded with a small amount of capital so that we
        // can test `get_targeted_long` when budget is the primary constraint.
        // Claire is funded with a large amount of capital so tha we can test
        // `get_targeted_long` when budget is not a constraint.
        let mut rng = thread_rng();
        let chain = TestChain::new(3).await?;
        let (alice, bob, claire) = (
            chain.accounts()[0].clone(),
            chain.accounts()[1].clone(),
            chain.accounts()[2].clone(),
        );
        let mut alice =
            Agent::new(chain.client(alice).await?, chain.addresses().clone(), None).await?;
        let mut bob = Agent::new(chain.client(bob).await?, chain.addresses(), None).await?;
        let mut claire = Agent::new(chain.client(claire).await?, chain.addresses(), None).await?;
        let config = bob.get_config().clone();

        for _ in 0..*FUZZ_RUNS {
            // Snapshot the chain.
            let id = chain.snapshot().await?;

            // Fund Alice and Bob.
            let fixed_rate = rng.gen_range(fixed!(0.01e18)..=fixed!(0.1e18));
            let contribution = rng.gen_range(fixed!(10_000e18)..=fixed!(500_000_000e18));
            let budget = rng.gen_range(fixed!(10e18)..=fixed!(500_000_000e18));
            alice.fund(contribution).await?; // large budget for initializing the pool
            bob.fund(budget).await?; // small budget for resource-constrained targeted longs
            claire.fund(contribution).await?; // large budget for unconstrained targeted longs

            // Alice initializes the pool.
            alice.initialize(fixed_rate, contribution, None).await?;

            // Some of the checkpoint passes and variable interest accrues.
            alice
                .checkpoint(alice.latest_checkpoint().await?, None)
                .await?;
            let rate = rng.gen_range(fixed!(0)..=fixed!(0.5e18));
            alice
                .advance_time(
                    rate,
                    FixedPoint::from(config.checkpoint_duration) * fixed!(0.5e18),
                )
                .await?;

            // Bob opens a targeted long.
            let max_spot_price = bob.get_state().await?.get_max_spot_price();
            let target_rate = fixed_rate - fixed!(1e18); // Bob can't afford this rate
            let targeted_long = bob.get_targeted_long(target_rate, None).await?;
            let spot_price_after_long = bob
                .get_state()
                .await?
                .get_spot_price_after_long(targeted_long);
            bob.open_long(targeted_long, None, None).await?;

            // Three things should be true after opening the long:
            //
            // 1. The pool's spot price is under the max spot price prior to
            //    considering fees
            // 2. The pool's solvency is above zero.
            // 3. Bob's budget is consumed.
            let is_under_max_price = max_spot_price > spot_price_after_long;
            let is_solvent = {
                let state = bob.get_state().await?;
                let error_tolerance = fixed!(1e5);
                state.get_solvency() > error_tolerance
            };
            let is_budget_consumed = {
                let error_tolerance = fixed!(1e5);
                bob.base() < error_tolerance
            };
            assert!(
                is_under_max_price && is_solvent && is_budget_consumed,
                "Invalid targeted long."
            );

            // Claire opens a targeted long.
            let max_spot_price = claire.get_state().await?.get_max_spot_price();
            let target_rate = fixed_rate - fixed!(0.1e18); // Claire can afford this rate
            let targeted_long = claire.get_targeted_long(target_rate, None).await?;
            let spot_price_after_long = claire
                .get_state()
                .await?
                .get_spot_price_after_long(targeted_long);
            claire.open_long(targeted_long, None, None).await?;

            // Four things should be true after opening the long:
            //
            // 1. The pool's spot price is under the max spot price prior to
            //    considering fees
            // 2. The pool's solvency is above zero.
            // 3. Claire's budget is not consumed.
            // 4. The spot rate is close to the target rate
            let is_under_max_price = max_spot_price > spot_price_after_long;
            let is_solvent = {
                let state = claire.get_state().await?;
                let error_tolerance = fixed!(1e5);
                state.get_solvency() > error_tolerance
            };
            let is_budget_consumed = {
                let error_tolerance = fixed!(1e18);
                claire.base() > error_tolerance
            };
            let does_target_match_spot_rate = {
                let state = claire.get_state().await?;
                let fixed_rate = state.get_spot_rate();
                let error_tolerance = fixed!(1e18);
                if fixed_rate > target_rate {
                    fixed_rate - target_rate < error_tolerance
                } else {
                    target_rate - fixed_rate < error_tolerance
                }
            };
            assert!(
                is_under_max_price
                    && is_solvent
                    && is_budget_consumed
                    && does_target_match_spot_rate,
                "Invalid targeted long."
            );

            // Revert to the snapshot and reset the agent's wallets.
            chain.revert(id).await?;
            alice.reset(Default::default());
            bob.reset(Default::default());
            claire.reset(Default::default());
        }

        Ok(())
    }
}
