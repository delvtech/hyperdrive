use ethers::types::{I256, U256};
use eyre::{eyre, Result};
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

use crate::{State, YieldSpace};

impl State {
    /// Gets a target long that can be opened given a budget to achieve a desired fixed rate.
    pub fn get_targeted_long_with_budget<F: Into<FixedPoint>, I: Into<I256>>(
        &self,
        budget: F,
        target_rate: F,
        checkpoint_exposure: I,
        maybe_max_iterations: Option<usize>,
    ) -> Result<FixedPoint> {
        let budget = budget.into();
        match self.get_targeted_long(target_rate, checkpoint_exposure, maybe_max_iterations) {
            Ok(long_amount) => Ok(long_amount.min(budget)),
            Err(error) => Err(error),
        }
    }

    /// Gets a target long that can be opened given a desired fixed rate.
    pub fn get_targeted_long<F: Into<FixedPoint>, I: Into<I256>>(
        &self,
        target_rate: F,
        checkpoint_exposure: I,
        maybe_max_iterations: Option<usize>,
    ) -> Result<FixedPoint> {
        let target_rate = target_rate.into();
        let checkpoint_exposure = checkpoint_exposure.into();

        // Estimate the long that achieves a target rate.
        let (target_share_reserves, target_bond_reserves) =
            self.reserves_given_rate_ignoring_exposure(target_rate);
        let (target_base_delta, target_bond_delta) =
            self.trade_deltas_from_reserves(target_share_reserves, target_bond_reserves);
        println!("spot_target_bond_delta {:#?}", target_bond_delta);
        println!("spot_target_base_delta {:#?}", target_base_delta);

        // Determine what rate was achieved.
        let resulting_rate = self.rate_after_long(target_base_delta); // ERROR in here
        let resulting_price = self.price_for_given_rate(resulting_rate);
        println!("resulting_rate {:#?}", resulting_rate);
        println!("resulting_price {:#?}", resulting_price);

        let abs_rate_error = self.abs_rate_error(target_rate, resulting_rate);
        // TODO: ask alex about an appropriate tolerance for the rate error
        let allowable_error = fixed!(1e5);
        // Verify solvency and target rate.
        if self
            .solvency_after_long(target_base_delta, target_bond_delta, checkpoint_exposure)
            .is_some()
            && abs_rate_error < allowable_error
        {
            return Ok(target_base_delta);
        } else {
            // Adjust your first guess
            let mut possible_target_base_amount = self.ze() - self.minimum_share_reserves();
            // // TODO: Need to come up with a smarter and safe first guess
            // let mut possible_target_base_amount = if resulting_rate > target_rate {
            //     spot_target_base_amount / fixed!(15e17) // overshot; need a smaller long
            // } else {
            //     spot_target_base_amount * fixed!(15e17) // undershot; need a larger long
            // };
            // Iteratively find a solution
            for _ in 0..maybe_max_iterations.unwrap_or(7) {
                let possible_target_bond_amount = self
                    .calculate_open_long(possible_target_base_amount)
                    .unwrap();
                // TODO: make optional bond amount all the way down (through calc_spot_price_after_long) to avoid
                // extra `calculate_open_long`
                let resulting_rate = self.rate_after_long(possible_target_base_amount);
                let abs_rate_error = self.abs_rate_error(target_rate, resulting_rate);

                // If we've done it (solvent & within error), then return the value.
                if self
                    .solvency_after_long(
                        possible_target_base_amount,
                        possible_target_bond_amount,
                        checkpoint_exposure,
                    )
                    .is_some()
                    && abs_rate_error < allowable_error
                {
                    return Ok(possible_target_base_amount);

                // Otherwise perform another iteration.
                } else {
                    let negative_loss_derivative = match self
                        .negative_targeted_loss_derivative(possible_target_base_amount)
                    {
                        Some(derivative) => derivative,
                        None => {
                            return Err(eyre!(
                            "get_targeted_long: Invalid value when calculating targeted loss derivative.",
                        ));
                        }
                    };
                    let loss = self.targeted_loss(target_rate, possible_target_base_amount);

                    // adding the negative loss derivative instead of subtracting the loss derivative
                    possible_target_base_amount =
                        possible_target_base_amount + loss / negative_loss_derivative;
                }
            }

            // If we hit max iterations and never were within error, check solvency & return.
            if self
                .solvency_after_long(
                    possible_target_base_amount,
                    self.calculate_open_long(possible_target_base_amount)
                        .unwrap(),
                    checkpoint_exposure,
                )
                .is_some()
            {
                return Ok(possible_target_base_amount);

            // Otherwise we'll return an error.
            } else {
                return Err(eyre!("Initial guess in `get_targeted_long` is insolvent."));
            }
        }
    }

    fn price_for_given_rate(&self, rate: FixedPoint) -> FixedPoint {
        let annualized_time =
            self.position_duration() / FixedPoint::from(U256::from(60 * 60 * 24 * 365));
        fixed!(1e18) / (rate * annualized_time + fixed!(1e18))
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
    fn negative_rate_after_long_derivative(&self, base_amount: FixedPoint) -> Option<FixedPoint> {
        let annualized_time =
            self.position_duration() / FixedPoint::from(U256::from(60 * 60 * 24 * 365));
        let price = self.get_spot_price_after_long(base_amount);
        let price_derivative = match self.price_after_long_derivative(base_amount) {
            Some(derivative) => derivative,
            None => return None,
        };

        // The actual equation we want to solve is:
        // (-p' * p * d - (1-p) (p'd + p)) / (p * d)^2
        // We can do a trick to return a positive-only version and
        // indicate that it should be negative in the fn name.
        // -1 * -1 * (-p' * p * d - (1-p) (p'*d + p)) / (p * d)^2
        // -1 * (p' * p * d + (1-p) (p'*d + p)) / (p * d)^2
        Some(
            (price_derivative * price * annualized_time
                + (fixed!(1e18) - price) * (price_derivative * annualized_time + price))
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
        let inner_denominator =
            self.bond_reserves() - self.calculate_open_long(base_amount).unwrap();

        let inner_derivative = (inner_denominator * inner_numerator_derivative
            + inner_numerator * long_amount_derivative)
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
        // This should never happen, but jic
        if target_rate > resulting_rate {
            panic!("We overshot the zero-crossing!");
        }
        resulting_rate - target_rate
    }

    /// Derivative of the targeted long loss
    /// TODO: Add docs
    fn negative_targeted_loss_derivative(&self, base_amount: FixedPoint) -> Option<FixedPoint> {
        match self.negative_rate_after_long_derivative(base_amount) {
            Some(derivative) => return Some(derivative),
            None => return None,
        }
    }

    /// Calculate the base & bond deltas from the current state given desired new reserve levels
    /// TODO: Add docs
    fn trade_deltas_from_reserves(
        &self,
        share_reserves: FixedPoint,
        bond_reserves: FixedPoint,
    ) -> (FixedPoint, FixedPoint) {
        // The spot max base amount is given by:
        //
        // spot_target_base_amount = c * (z_t - z)
        let base_delta =
            (share_reserves - self.effective_share_reserves()) * self.vault_share_price();

        // The spot max bond amount is given by:
        //
        // spot_target_bond_amount = (y - y_t) - c(x)
        let bond_delta =
            (self.bond_reserves() - bond_reserves) - self.open_long_curve_fees(base_delta);

        (base_delta, bond_delta)
    }

    /// Calculates the long that should be opened to hit a target interest rate.
    /// This calculation does not take Hyperdrive's solvency constraints into account and shouldn't be used directly.
    fn reserves_given_rate_ignoring_exposure<F: Into<FixedPoint>>(
        &self,
        target_rate: F,
    ) -> (FixedPoint, FixedPoint) {
        //
        // TODO: Docstring
        //
        let target_rate = target_rate.into();
        let annualized_time =
            self.position_duration() / FixedPoint::from(U256::from(60 * 60 * 24 * 365));
        let c_over_mu = self
            .vault_share_price()
            .div_up(self.initial_vault_share_price());
        let scaled_rate = (target_rate.mul_up(annualized_time) + fixed!(1e18))
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

        (target_share_reserves, target_bond_reserves)
    }
}

// TODO: Modify this test to use mock for state updates
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

    // TODO:
    // #[traced_test]
    // #[tokio::test]
    // async fn test_reserves_given_rate_ignoring_solvency() -> Result<()> {
    // }

    #[traced_test]
    #[tokio::test]
    async fn test_get_targeted_long_with_budget() -> Result<()> {
        // Spawn a test chain and create two agents -- Alice and Bob.
        // Alice is funded with a large amount of capital so that she can initialize
        // the pool. Bob is funded with a random amount of capital so that we
        // can test `get_targeted_long` when budget is the primary constraint
        // and when it is not.

        // Initialize a test chain; don't need mocks because we want state updates.
        let chain = TestChain::new(2).await?;

        // Grab accounts for Alice, Bob, and Claire.
        let (alice, bob) = (chain.accounts()[0].clone(), chain.accounts()[1].clone());

        // Initialize Alice, Bob, and Claire as Agents.
        let mut alice =
            Agent::new(chain.client(alice).await?, chain.addresses().clone(), None).await?;
        let mut bob = Agent::new(chain.client(bob).await?, chain.addresses(), None).await?;
        let config = bob.get_config().clone();

        // Fuzz test
        let mut rng = thread_rng();
        for _ in 0..*FUZZ_RUNS {
            // Snapshot the chain.
            let id = chain.snapshot().await?;

            // Fund Alice and Bob.
            let contribution = fixed!(1_000_000e18);
            alice.fund(contribution).await?; // large budget for initializing the pool
            let budget = rng.gen_range(fixed!(10e18)..=fixed!(500_000_000e18));
            bob.fund(budget).await?; // small budget for resource-constrained targeted longs

            // Alice initializes the pool.
            let initial_fixed_rate = rng.gen_range(fixed!(0.01e18)..=fixed!(0.1e18));
            alice
                .initialize(initial_fixed_rate, contribution, None)
                .await?;
            println!("initial state: {:#?}", alice.get_state().await?);
            println!("initial_fixed_rate {:#?}", initial_fixed_rate);

            // Some of the checkpoint passes and variable interest accrues.
            alice
                .checkpoint(alice.latest_checkpoint().await?, None)
                .await?;
            let variable_rate = rng.gen_range(fixed!(0)..=fixed!(0.5e18));
            alice
                .advance_time(
                    variable_rate,
                    FixedPoint::from(config.checkpoint_duration) * fixed!(0.5e18),
                )
                .await?;

            // Bob opens a targeted long.
            let max_spot_price_before_long = bob.get_state().await?.get_max_spot_price();
            let target_rate = initial_fixed_rate / fixed!(2e18);
            println!("target_rate {:#?}", target_rate);
            let targeted_long = bob.get_targeted_long(target_rate, None).await?;
            println!("targeted_long {:#?}", targeted_long);
            bob.open_long(targeted_long, None, None).await?;

            // Three things should be true after opening the long:
            //
            // 1. The pool's spot price is under the max spot price prior to
            //    considering fees
            // 2. The pool's solvency is above zero.
            // 3. IF Bob's budget is not consumed; then new rate is the target rate
            let spot_price_after_long = bob.get_state().await?.get_spot_price();
            let is_under_max_price = max_spot_price_before_long > spot_price_after_long;
            let is_solvent = {
                let state = bob.get_state().await?;
                let error_tolerance = fixed!(1e5);
                state.get_solvency() > error_tolerance
            };
            assert!(is_under_max_price && is_solvent, "Invalid targeted long.");

            let is_budget_consumed = {
                let error_tolerance = fixed!(1e5);
                bob.base() < error_tolerance
            };
            let is_rate_achieved = {
                let state = bob.get_state().await?;
                let new_rate = state.get_spot_rate();
                let error_tolerance = fixed!(1e5);
                if new_rate > target_rate {
                    new_rate - target_rate < error_tolerance
                } else {
                    target_rate - new_rate < error_tolerance
                }
            };
            if !is_budget_consumed {
                assert!(is_rate_achieved, "Invalid targeted long.");
            }

            // Revert to the snapshot and reset the agent's wallets.
            chain.revert(id).await?;
            alice.reset(Default::default());
            bob.reset(Default::default());
        }

        Ok(())
    }
}
