use ethers::types::I256;
use eyre::{eyre, Result};
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

use crate::{State, YieldSpace};

impl State {
    /// Gets a target long that can be opened given a budget to achieve a desired fixed rate.
    ///
    /// If the long amount to reach the target is greater than the budget, the budget is returned.
    /// If the long amount to reach the target is invalid (i.e. it would produce an insolvent pool), then
    /// an error is thrown, and the user is advised to use [calculate_max_long](long::max::calculate_max_long).
    pub fn calculate_targeted_long_with_budget<
        F1: Into<FixedPoint>,
        F2: Into<FixedPoint>,
        F3: Into<FixedPoint>,
        I: Into<I256>,
    >(
        &self,
        budget: F1,
        target_rate: F2,
        checkpoint_exposure: I,
        maybe_max_iterations: Option<usize>,
        maybe_allowable_error: Option<F3>,
    ) -> Result<FixedPoint> {
        let budget = budget.into();
        match self.calculate_targeted_long(
            target_rate,
            checkpoint_exposure,
            maybe_max_iterations,
            maybe_allowable_error,
        ) {
            Ok(long_amount) => Ok(long_amount.min(budget)),
            Err(error) => Err(error),
        }
    }

    /// Gets a target long that can be opened to achieve a desired fixed rate.
    fn calculate_targeted_long<F1: Into<FixedPoint>, F2: Into<FixedPoint>, I: Into<I256>>(
        &self,
        target_rate: F1,
        checkpoint_exposure: I,
        maybe_max_iterations: Option<usize>,
        maybe_allowable_error: Option<F2>,
    ) -> Result<FixedPoint> {
        let target_rate = target_rate.into();
        let checkpoint_exposure = checkpoint_exposure.into();
        let allowable_error = match maybe_allowable_error {
            Some(allowable_error) => allowable_error.into(),
            None => fixed!(1e14),
        };

        // Check input args.
        let current_rate = self.calculate_spot_rate();
        if target_rate > current_rate {
            return Err(eyre!(
                "target_rate = {} argument must be less than the current_rate = {} for a targeted long.",
                target_rate, current_rate,
            ));
        }

        // Estimate the long that achieves a target rate.
        let (target_share_reserves, target_bond_reserves) =
            self.reserves_given_rate_ignoring_exposure(target_rate);
        let (mut target_base_delta, target_bond_delta) =
            self.long_trade_deltas_from_reserves(target_share_reserves, target_bond_reserves);

        // Determine what rate was achieved.
        let resulting_rate =
            self.calculate_spot_rate_after_long(target_base_delta, Some(target_bond_delta))?;

        // The estimated long will usually underestimate because the realized price
        // should always be greater than the spot price.
        //
        // However, if we overshot the zero-crossing (due to errors arising from FixedPoint arithmetic),
        // then either return or reduce the starting base amount and start on Newton's method.
        if target_rate > resulting_rate {
            let rate_error = target_rate - resulting_rate;

            // If we were still close enough and solvent, return.
            if self
                .solvency_after_long(target_base_delta, target_bond_delta, checkpoint_exposure)
                .is_some()
                && rate_error < allowable_error
            {
                return Ok(target_base_delta);
            }
            // Else, cut the initial guess down by an order of magnitude and go to Newton's method.
            else {
                target_base_delta = target_base_delta / fixed!(10e18);
            }
        }
        // Else check if we are close enough to return.
        else {
            // If solvent & within the allowable error, stop here.
            let rate_error = resulting_rate - target_rate;
            if self
                .solvency_after_long(target_base_delta, target_bond_delta, checkpoint_exposure)
                .is_some()
                && rate_error < allowable_error
            {
                return Ok(target_base_delta);
            }
        }

        // Iterate to find a solution.
        // We can use the initial guess as a starting point since we know it is less than the target.
        let mut possible_target_base_delta = target_base_delta;

        // Iteratively find a solution
        for _ in 0..maybe_max_iterations.unwrap_or(7) {
            let possible_target_bond_delta = self
                .calculate_open_long(possible_target_base_delta)
                .unwrap();
            let resulting_rate = self.calculate_spot_rate_after_long(
                possible_target_base_delta,
                Some(possible_target_bond_delta),
            )?;

            // We assume that the loss is positive only because Newton's
            // method will always underestimate.
            if target_rate > resulting_rate {
                return Err(eyre!(
                    "We overshot the zero-crossing during Newton's method.",
                ));
            }
            // The optimization loss can be the difference without abs or squaring
            // because of the above check.
            let loss = resulting_rate - target_rate;

            // If we've done it (solvent & within error), then return the value.
            if self
                .solvency_after_long(
                    possible_target_base_delta,
                    possible_target_bond_delta,
                    checkpoint_exposure,
                )
                .is_some()
                && loss < allowable_error
            {
                return Ok(possible_target_base_delta);
            }
            // Otherwise perform another iteration.
            else {
                // The derivative of the loss is $l'(x) = r'(x)$.
                // We return $-l'(x)$ because $r'(x)$ is negative, which
                // can't be represented with FixedPoint.
                let negative_loss_derivative = self.rate_after_long_derivative_negation(
                    possible_target_base_delta,
                    possible_target_bond_delta,
                )?;

                // Adding the negative loss derivative instead of subtracting the loss derivative
                // ∆x_{n+1} = ∆x_{n} - l / l'
                //          = ∆x_{n} + l / (-l')
                possible_target_base_delta =
                    possible_target_base_delta + loss / negative_loss_derivative;
            }
        }

        // Final solvency check.
        if self
            .solvency_after_long(
                possible_target_base_delta,
                self.calculate_open_long(possible_target_base_delta)
                    .unwrap(),
                checkpoint_exposure,
            )
            .is_none()
        {
            return Err(eyre!("Guess in `calculate_targeted_long` is insolvent."));
        }

        // Final accuracy check.
        let possible_target_bond_delta = self
            .calculate_open_long(possible_target_base_delta)
            .unwrap();
        let resulting_rate = self.calculate_spot_rate_after_long(
            possible_target_base_delta,
            Some(possible_target_bond_delta),
        )?;
        if target_rate > resulting_rate {
            return Err(eyre!(
                "We overshot the zero-crossing after Newton's method.",
            ));
        }
        let loss = resulting_rate - target_rate;
        if loss >= allowable_error {
            return Err(eyre!(
                "Unable to find an acceptable loss with max iterations. Final loss = {}.",
                loss
            ));
        }

        Ok(possible_target_base_delta)
    }

    /// The derivative of the equation for calculating the rate after a long.
    ///
    /// For some $r = (1 - p(x)) / (p(x) \cdot t)$, where $p(x)$
    /// is the spot price after a long of `delta_base`$= x$ was opened and $t$
    /// is the annualized position duration, the rate derivative is:
    ///
    /// $$
    /// r'(x) = \frac{(-p'(x) \cdot p(x) t - (1 - p(x)) (p'(x) \cdot t))}{(p(x) \cdot t)^2} //
    /// r'(x) = \frac{-p'(x)}{t \cdot p(x)^2}
    /// $$
    ///
    /// We return $-r'(x)$ because negative numbers cannot be represented by FixedPoint.
    fn rate_after_long_derivative_negation(
        &self,
        base_amount: FixedPoint,
        bond_amount: FixedPoint,
    ) -> Result<FixedPoint> {
        let price = self.calculate_spot_price_after_long(base_amount, Some(bond_amount))?;
        let price_derivative = self.price_after_long_derivative(base_amount, bond_amount)?;
        // The actual equation we want to represent is:
        // r' = -p' / (t \cdot p^2)
        // We can do a trick to return a positive-only version and
        // indicate that it should be negative in the fn name.
        // We use price * price instead of price.pow(fixed!(2e18)) to avoid error introduced by pow.
        Ok(price_derivative / (self.annualized_position_duration() * price * price))
    }

    /// The derivative of the price after a long.
    ///
    /// The price after a long that moves shares by $\Delta z$ and bonds by $\Delta y$
    /// is equal to
    ///
    /// $$
    /// p(\Delta z) = (\frac{\mu \cdot (z_{0} + \Delta z - (\zeta_{0} + \Delta \zeta))}{y - \Delta y})^{t_{s}}
    /// $$
    ///
    /// where $t_{s}$ is the time stretch constant and $z_{e,0}$ is the initial
    /// effective share reserves, and $\zeta$ is the zeta adjustment.
    /// The zeta adjustment is constant when opening a long, i.e.
    /// $\Delta \zeta = 0$, so we drop the subscript. Equivalently, for some
    /// amount of `delta_base`$= x$ provided to open a long, we can write:
    ///
    /// $$
    /// p(x) = (\frac{\mu \cdot (z_{e,0} + \frac{x}{c} - g(x) - \zeta)}{y_0 - y(x)})^{t_{s}}
    /// $$
    ///
    /// where $g(x)$ is the [open_long_governance_fee](long::fees::open_long_governance_fee),
    /// $y(x)$ is the [long_amount](long::open::calculate_open_long),
    ///
    ///
    /// To compute the derivative, we first define some auxiliary variables:
    ///
    /// $$
    /// a(x) = \mu (z_{0} + \frac{x}{c} - g(x) - \zeta) \\
    /// b(x) = y_0 - y(x) \\
    /// v(x) = \frac{a(x)}{b(x)}
    /// $$
    ///
    /// and thus $p(x) = v(x)^t_{s}$. Given these, we can write out intermediate derivatives:
    ///
    /// $$
    /// a'(x) = \frac{\mu}{c} - g'(x) \\
    /// b'(x) = -y'(x) \\
    /// v'(x) = \frac{b(x) \cdot a'(x) - a(x) \cdot b'(x)}{b(x)^2}
    /// $$
    ///
    /// And finally, the price after long derivative is:
    ///
    /// $$
    /// p'(x) = v'(x) \cdot t_{s} \cdot v(x)^(t_{s} - 1)
    /// $$
    ///
    fn price_after_long_derivative(
        &self,
        base_amount: FixedPoint,
        bond_amount: FixedPoint,
    ) -> Result<FixedPoint> {
        // g'(x)
        let gov_fee_derivative = self.governance_lp_fee()
            * self.curve_fee()
            * (fixed!(1e18) - self.calculate_spot_price());

        // a(x) = mu * (z_{e,0} + x/c - g(x))
        let inner_numerator = self.mu()
            * (self.ze() + base_amount / self.vault_share_price()
                - self.open_long_governance_fee(base_amount));

        // a'(x) = mu / c - g'(x)
        let inner_numerator_derivative = self.mu() / self.vault_share_price() - gov_fee_derivative;

        // b(x) = y_0 - y(x)
        let inner_denominator = self.bond_reserves() - bond_amount;

        // b'(x) = -y'(x)
        let long_amount_derivative = match self.long_amount_derivative(base_amount) {
            Some(derivative) => derivative,
            None => return Err(eyre!("long_amount_derivative failure.")),
        };

        // v(x) = a(x) / b(x)
        // v'(x) = ( b(x) * a'(x) - a(x) * b'(x) ) / b(x)^2
        //       = ( b(x) * a'(x) + a(x) * -b'(x) ) / b(x)^2
        // Note that we are adding the negative b'(x) to avoid negative fixedpoint numbers
        let inner_derivative = (inner_denominator * inner_numerator_derivative
            + inner_numerator * long_amount_derivative)
            / (inner_denominator * inner_denominator);

        // p'(x) = v'(x) * t_s * v(x)^(t_s - 1)
        // p'(x) = v'(x) * t_s * v(x)^(-1)^(1 - t_s)
        // v(x) is flipped to (denominator / numerator) to avoid a negative exponent
        Ok(inner_derivative
            * self.time_stretch()
            * (inner_denominator / inner_numerator).pow(fixed!(1e18) - self.time_stretch()))
    }

    /// Calculate the base & bond deltas for a long trade that moves the current
    /// state to the given desired ending reserve levels.
    ///
    /// Given a target ending pool share reserves, $z_t$, and bond reserves, $y_t$,
    /// the trade deltas to achieve that state would be:
    ///
    /// $$
    /// \Delta x = c \cdot (z_t - z_{e,0}) \\
    /// \Delta y = y - y_t - c(\Delta x)
    /// $$
    ///
    /// where $c$ is the vault share price and
    /// $c(\Delta x)$ is the (open_long_curve_fee)[long::fees::open_long_curve_fees].
    fn long_trade_deltas_from_reserves(
        &self,
        ending_share_reserves: FixedPoint,
        ending_bond_reserves: FixedPoint,
    ) -> (FixedPoint, FixedPoint) {
        let base_delta =
            (ending_share_reserves - self.effective_share_reserves()) * self.vault_share_price();
        let bond_delta =
            (self.bond_reserves() - ending_bond_reserves) - self.open_long_curve_fees(base_delta);
        (base_delta, bond_delta)
    }
}

#[cfg(test)]
mod tests {
    use ethers::types::U256;
    use fixed_point_macros::uint256;
    use rand::{thread_rng, Rng};
    use test_utils::{chain::TestChain, constants::FUZZ_RUNS};
    use tracing_test::traced_test;

    use super::*;

    #[traced_test]
    #[tokio::test]
    async fn test_calculate_targeted_long_with_budget() -> Result<()> {
        // Spawn a test chain and create two agents -- Alice and Bob.
        // Alice is funded with a large amount of capital so that she can initialize
        // the pool. Bob is funded with a random amount of capital so that we
        // can test `calculate_targeted_long` when budget is the primary constraint
        // and when it is not.

        let allowable_solvency_error = fixed!(1e5);
        let allowable_budget_error = fixed!(1e5);
        let allowable_rate_error = fixed!(1e11);
        let num_newton_iters = 7;

        // Initialize a test chain.
        let chain = TestChain::new().await?;
        let mut alice = chain.alice().await?;
        let mut bob = chain.bob().await?;
        let config = bob.get_config().clone();

        // Fuzz test
        let mut rng = thread_rng();
        for _ in 0..*FUZZ_RUNS {
            // Snapshot the chain.
            let id = chain.snapshot().await?;

            // Fund Alice and Bob.
            // Large budget for initializing the pool.
            let contribution = fixed!(1_000_000e18);
            alice.fund(contribution).await?;
            // Small lower bound on the budget for resource-constrained targeted longs.
            let budget = rng.gen_range(fixed!(10e18)..=fixed!(500_000_000e18));

            // Alice initializes the pool.
            let initial_fixed_rate = rng.gen_range(fixed!(0.01e18)..=fixed!(0.1e18));
            alice
                .initialize(initial_fixed_rate, contribution, None)
                .await?;

            // Half the time we will open a long & let it mature.
            if rng.gen_range(0..=1) == 0 {
                // Open a long.
                let max_long =
                    bob.get_state()
                        .await?
                        .calculate_max_long(U256::MAX, I256::from(0), None);
                let long_amount =
                    (max_long / fixed!(100e18)).max(config.minimum_transaction_amount.into());
                bob.fund(long_amount + budget).await?;
                bob.open_long(long_amount, None, None).await?;
                // Advance time to just after maturity.
                let variable_rate = rng.gen_range(fixed!(0)..=fixed!(0.5e18));
                let time_amount = FixedPoint::from(config.position_duration) * fixed!(105e17); // 1.05 * position_duraiton
                alice.advance_time(variable_rate, time_amount).await?;
                // Checkpoint to auto-close the position.
                alice
                    .checkpoint(alice.latest_checkpoint().await?, uint256!(0), None)
                    .await?;
            }
            // Else we will just fund a random budget amount and do the targeted long.
            else {
                bob.fund(budget).await?;
            }

            // Some of the checkpoint passes and variable interest accrues.
            alice
                .checkpoint(alice.latest_checkpoint().await?, uint256!(0), None)
                .await?;
            let variable_rate = rng.gen_range(fixed!(0)..=fixed!(0.5e18));
            alice
                .advance_time(
                    variable_rate,
                    FixedPoint::from(config.checkpoint_duration) * fixed!(0.5e18),
                )
                .await?;

            // Get a targeted long amount.
            // TODO: explore tighter bounds on this.
            let target_rate = bob.get_state().await?.calculate_spot_rate()
                / rng.gen_range(fixed!(1.0001e18)..=fixed!(10e18));
            // let target_rate = initial_fixed_rate / fixed!(2e18);
            let targeted_long_result = bob
                .calculate_targeted_long(
                    target_rate,
                    Some(num_newton_iters),
                    Some(allowable_rate_error),
                )
                .await;

            // Bob opens a targeted long.
            let current_state = bob.get_state().await?;
            let max_spot_price_before_long = current_state.calculate_max_spot_price();
            match targeted_long_result {
                // If the code ran without error, open the long
                Ok(targeted_long) => {
                    bob.open_long(targeted_long, None, None).await?;
                }

                // Else parse the error for a to improve error messaging.
                Err(e) => {
                    // If the fn failed it's possible that the target rate would be insolvent.
                    if e.to_string()
                        .contains("Unable to find an acceptable loss with max iterations")
                    {
                        let max_long = bob.calculate_max_long(None).await?;
                        let rate_after_max_long =
                            current_state.calculate_spot_rate_after_long(max_long, None)?;
                        // If the rate after the max long is at or below the target, then we could have hit it.
                        if rate_after_max_long <= target_rate {
                            return Err(eyre!(
                                "ERROR {}\nA long that hits the target rate exists but was not found.",
                                e
                            ));
                        }
                        // Otherwise the target would have resulted in insolvency and wasn't possible.
                        else {
                            return Err(eyre!(
                                "ERROR {}\nThe target rate would result in insolvency.",
                                e
                            ));
                        }
                    }
                    // If the error is not the one we're looking for, return it, causing the test to fail.
                    else {
                        return Err(e);
                    }
                }
            }

            // Three things should be true after opening the long:
            //
            // 1. The pool's spot price is under the max spot price prior to
            //    considering fees
            // 2. The pool's solvency is above zero.
            // 3. IF Bob's budget is not consumed; then new rate is close to the target rate

            // Check that our resulting price is under the max
            let current_state = bob.get_state().await?;
            let spot_price_after_long = current_state.calculate_spot_price();
            assert!(
                max_spot_price_before_long > spot_price_after_long,
                "Resulting price is greater than the max."
            );

            // Check solvency
            let is_solvent = { current_state.calculate_solvency() > allowable_solvency_error };
            assert!(is_solvent, "Resulting pool state is not solvent.");

            let new_rate = current_state.calculate_spot_rate();
            // If the budget was NOT consumed, then we assume the target was hit.
            if !(bob.base() <= allowable_budget_error) {
                // Actual price might result in long overshooting the target.
                let abs_error = if target_rate > new_rate {
                    target_rate - new_rate
                } else {
                    new_rate - target_rate
                };
                assert!(
                    abs_error <= allowable_rate_error,
                    "target_rate was {}, realized rate is {}. abs_error={} was not <= {}.",
                    target_rate,
                    new_rate,
                    abs_error,
                    allowable_rate_error
                );
            }
            // Else, we should have undershot,
            // or by some coincidence the budget was the perfect amount
            // and we hit the rate exactly.
            else {
                assert!(
                    new_rate >= target_rate,
                    "The new_rate={} should be >= target_rate={} when budget constrained.",
                    new_rate,
                    target_rate
                );
            }

            // Revert to the snapshot and reset the agent's wallets.
            chain.revert(id).await?;
            alice.reset(Default::default());
            bob.reset(Default::default());
        }

        Ok(())
    }
}
