use ethers::{
    providers::maybe,
    types::{I256, U256},
};
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
        let (spot_target_base_amount, spot_target_bond_amount) =
            self.spot_targeted_long(target_rate);
        let resulting_rate = self.rate_after_long(spot_target_base_amount);
        let abs_rate_error = self.abs_rate_error(target_rate, resulting_rate);
        // TODO: ask alex about an appropriate tolerance for the rate error
        let allowable_error = fixed!(1e5);
        // Verify solvency and target rate
        if self
            .solvency_after_long(
                spot_target_base_amount,
                spot_target_bond_amount,
                checkpoint_exposure,
            )
            .is_some()
            && abs_rate_error < allowable_error
        {
            return spot_target_base_amount.min(budget);
        } else {
            // Adjust your first guess
            // TODO: Need to come up with a smarter and safe first guess
            let mut possible_target_base_amount = if resulting_rate > target_rate {
                spot_target_base_amount / fixed!(15e17) // overshot; need a smaller long
            } else {
                spot_target_base_amount * fixed!(15e17) // undershot; need a larger long
            };
            // Iteratively find a solution
            for _ in 0..maybe_max_iterations.unwrap_or(7) {
                let possible_target_bond_amount =
                    self.calculate_open_long(possible_target_base_amount);
                let resulting_rate = self.rate_after_long(possible_target_base_amount);
                let abs_rate_error = self.abs_rate_error(target_rate, resulting_rate);
                if self
                    .solvency_after_long(
                        possible_target_base_amount,
                        possible_target_bond_amount,
                        checkpoint_exposure,
                    )
                    .is_some()
                    && abs_rate_error < allowable_error
                {
                    return possible_target_base_amount.max(budget);
                } else {
                    possible_target_base_amount = possible_target_base_amount
                        + self.targeted_loss_derivative(target_rate, possible_target_base_amount);
                }
            }
            if self
                .solvency_after_long(
                    possible_target_base_amount,
                    self.calculate_open_long(possible_target_base_amount),
                    checkpoint_exposure,
                )
                .is_some()
            {
                return possible_target_base_amount.max(budget);
            } else {
                panic!("Initial guess in `get_targeted_long` is insolvent.");
            }
        }
    }

    /// The non-negative error between a target rate and resulting rate
    /// TODO: Add docs
    fn abs_rate_error(&self, target_rate: FixedPoint, resulting_rate: FixedPoint) -> FixedPoint {
        if resulting_rate > target_rate {
            resulting_rate - target_rate
        } else {
            target_rate - resulting_rate
        }
    }

    /// The spot fixed rate after a long has been opened
    /// TODO: Add docs
    fn rate_after_long(&self, base_amount: FixedPoint) -> FixedPoint {
        let annualized_time =
            self.position_duration() / FixedPoint::from(U256::from(60 * 60 * 24 * 365));
        let resulting_price = self.get_spot_price_after_long(base_amount);
        (fixed!(1e18) - resulting_price) / (resulting_price * annualized_time)
    }

    /// The derivative of the equation for calculating the spot rate after a long
    /// TODO: Add docs
    fn rate_after_long_derivative(&self, base_amount: FixedPoint) -> Option<FixedPoint> {
        let annualized_time =
            self.position_duration() / FixedPoint::from(U256::from(60 * 60 * 24 * 365));
        let price = self.get_spot_price_after_long(base_amount);
        let price_derivative = match self.price_after_long_derivative(base_amount) {
            Some(derivative) => derivative,
            None => return None,
        };
        Some(
            (-price_derivative * price * annualized_time
                - (fixed!(1e18) - price) * (price_derivative * annualized_time + price),)
                / (price * annualized_time).pow(fixed!(2e18)),
        )
    }

    /// The derivative of the price after a long
    /// TODO: Add docs
    fn price_after_long_derivative(&self, base_amount: FixedPoint) -> Option<FixedPoint> {
        let long_amount_derivative = match self.long_amount_derivative(base_amount) {
            Some(derivative) => derivative,
            None => return None,
        };
        let initial_spot_price = self.get_spot_price();
        let gov_fee_derivative =
            self.governance_lp_fee() * self.curve_fee() * (fixed!(1e18) - initial_spot_price);
        let inner_numerator = self.mu()
            * (self.ze() + base_amount / self.vault_share_price()
                - self.open_long_governance_fee(base_amount)
                - self.zeta().into());
        let inner_numerator_derivative = self.mu() / self.vault_share_price() - gov_fee_derivative;
        let inner_denominator = self.bond_reserves() - self.calculate_open_long(base_amount);
        let inner_denominator_derivative = -long_amount_derivative;
        let inner_derivative = (inner_denominator * inner_numerator_derivative
            - inner_numerator * inner_denominator_derivative)
            / inner_denominator.pow(fixed!(2e18));
        return Some(
            inner_derivative
                * self.time_stretch()
                * (inner_numerator / inner_denominator).pow(self.time_stretch() - fixed!(1e18)),
        );
    }

    /// The loss used for the targeted long optimization process
    /// TODO: Add docs
    fn targeted_loss(&self, target_rate: FixedPoint, base_amount: FixedPoint) -> FixedPoint {
        let resulting_rate = self.rate_after_long(base_amount);
        let abs_rate_error = self.abs_rate_error(target_rate, resulting_rate);
        (fixed!(1e18) / fixed!(2e18)) * (abs_rate_error).pow(fixed!(2e18))
    }

    /// Derivative of the targeted long loss
    /// TODO: Add docs
    fn targeted_loss_derivative(
        &self,
        target_rate: FixedPoint,
        base_amount: FixedPoint,
    ) -> FixedPoint {
        (self.rate_after_long(base_amount) - target_rate)
            * self.rate_after_long_derivative(base_amount)
    }

    /// Calculates the long that should be opened to hit a target interest rate.
    /// This calculation does not take Hyperdrive's solvency constraints into account and shouldn't be used directly.
    fn spot_targeted_long<F: Into<FixedPoint>>(&self, target_rate: F) -> (FixedPoint, FixedPoint) {
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

        // The spot max base amount is given by:
        //
        // spot_target_base_amount = c * (z_t - z)
        let spot_target_base_amount =
            (target_share_reserves - self.effective_share_reserves()) * self.vault_share_price();

        // The spot max bond amount is given by:
        //
        // spot_target_bond_amount = (y - y_t) - c(x)
        let spot_target_bond_amount = (self.bond_reserves() - target_bond_reserves)
            - self.open_long_curve_fees(spot_target_base_amount);

        (spot_target_base_amount, spot_target_bond_amount)
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
