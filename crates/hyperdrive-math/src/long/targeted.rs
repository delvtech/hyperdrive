use ethers::types::{I256, U256};
use eyre::{eyre, Result};
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

use crate::{State, YieldSpace};

impl State {
    /// Gets a target long that can be opened given a budget to achieve a desired fixed rate.
    pub fn get_targeted_long_with_budget<
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
        match self.get_targeted_long(
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
    fn get_targeted_long<F1: Into<FixedPoint>, F2: Into<FixedPoint>, I: Into<I256>>(
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

        // Estimate the long that achieves a target rate.
        let (target_share_reserves, target_bond_reserves) =
            self.reserves_given_rate_ignoring_exposure(target_rate);
        let (target_base_delta, target_bond_delta) =
            self.trade_deltas_from_reserves(target_share_reserves, target_bond_reserves);

        // Determine what rate was achieved.
        let resulting_rate = self.rate_after_long(target_base_delta, Some(target_bond_delta));

        // The estimated long should always underestimate because the realized price
        // should always be greater than the spot price.
        if target_rate > resulting_rate {
            return Err(eyre!("get_targeted_long: We overshot the zero-crossing.",));
        }
        let rate_error = resulting_rate - target_rate;

        // Verify solvency and target rate.
        if self
            .solvency_after_long(target_base_delta, target_bond_delta, checkpoint_exposure)
            .is_some()
            && rate_error < allowable_error
        {
            return Ok(target_base_delta);
        } else {
            // We can use the initial guess as a starting point since we know it is less than the target.
            let mut possible_target_base_delta = target_base_delta;

            // Iteratively find a solution
            for _ in 0..maybe_max_iterations.unwrap_or(7) {
                let possible_target_bond_delta = self
                    .calculate_open_long(possible_target_base_delta)
                    .unwrap();
                let resulting_rate = self
                    .rate_after_long(possible_target_base_delta, Some(possible_target_bond_delta));

                // We assume that the loss is positive only because Newton's
                // method and the one-shot approximation will always underestimate.
                if target_rate > resulting_rate {
                    return Err(eyre!("get_targeted_long: We overshot the zero-crossing.",));
                }
                // The loss is $l(x) = r(x) - r_t$ for some rate after a long
                // is opened, $r(x)$, and target rate, $r_t$.
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

                // Otherwise perform another iteration.
                } else {
                    // The derivative of the loss is $l'(x) = r'(x)$.
                    // We return $-l'(x)$ because $r'(x)$ is negative, which
                    // can't be represented with FixedPoint.
                    let negative_loss_derivative = match self.rate_after_long_derivative_negation(
                        possible_target_base_delta,
                        possible_target_bond_delta,
                    ) {
                        Some(derivative) => derivative,
                        None => {
                            return Err(eyre!(
                            "get_targeted_long: Invalid value when calculating targeted loss derivative.",
                        ));
                        }
                    };

                    // Adding the negative loss derivative instead of subtracting the loss derivative
                    // ∆x_{n+1} = ∆x_{n} - l / l'
                    //          = ∆x_{n} + l / (-l')
                    possible_target_base_delta =
                        possible_target_base_delta + loss / negative_loss_derivative;
                }
            }

            // Final solvency check.
            if !self
                .solvency_after_long(
                    possible_target_base_delta,
                    self.calculate_open_long(possible_target_base_delta)
                        .unwrap(),
                    checkpoint_exposure,
                )
                .is_some()
            {
                return Err(eyre!("Guess in `get_targeted_long` is insolvent."));
            }

            // Final accuracy check.
            let possible_target_bond_delta = self
                .calculate_open_long(possible_target_base_delta)
                .unwrap();
            let resulting_rate =
                self.rate_after_long(possible_target_base_delta, Some(possible_target_bond_delta));
            if target_rate > resulting_rate {
                return Err(eyre!("get_targeted_long: We overshot the zero-crossing.",));
            }
            let loss = resulting_rate - target_rate;
            if !(loss < allowable_error) {
                return Err(eyre!(
                    "get_targeted_long: Unable to find an acceptible loss. Final loss = {}.",
                    loss
                ));
            }

            Ok(possible_target_base_delta)
        }
    }

    /// The fixed rate after a long has been opened.
    ///
    /// We calculate the rate for a fixed length of time as:
    /// $$
    /// r(x) = (1 - p(x)) / (p(x) t)
    /// $$
    ///
    /// where $p(x)$ is the spot price after a long for `delta_bonds`$= x$ and
    /// t is the normalized position druation.
    ///
    /// In this case, we use the resulting spot price after a hypothetical long
    /// for `base_amount` is opened.
    fn rate_after_long(
        &self,
        base_amount: FixedPoint,
        bond_amount: Option<FixedPoint>,
    ) -> FixedPoint {
        let annualized_time =
            self.position_duration() / FixedPoint::from(U256::from(60 * 60 * 24 * 365));
        let resulting_price = self.get_spot_price_after_long(base_amount, bond_amount);
        (fixed!(1e18) - resulting_price) / (resulting_price * annualized_time)
    }

    /// The derivative of the equation for calculating the rate after a long.
    ///
    /// For some $r = (1 - p(x)) / (p(x) * t)$, where $p(x)$
    /// is the spot price after a long of `delta_base`$= x$ was opened and $t$
    /// is the annualized position duration, the rate derivative is:
    ///
    /// $$
    /// r'(x) = \frac{(-p'(x) p(x) t - (1 - p(x)) (p'(x) t))}{(p(x) t)^2} //
    /// r'(x) = \frac{-p'(x)}{t p(x)^2}
    /// $$
    ///
    /// We return $-r'(x)$ because negative numbers cannot be represented by FixedPoint.
    fn rate_after_long_derivative_negation(
        &self,
        base_amount: FixedPoint,
        bond_amount: FixedPoint,
    ) -> Option<FixedPoint> {
        let annualized_time =
            self.position_duration() / FixedPoint::from(U256::from(60 * 60 * 24 * 365));
        let price = self.get_spot_price_after_long(base_amount, Some(bond_amount));
        let price_derivative = match self.price_after_long_derivative(base_amount, bond_amount) {
            Some(derivative) => derivative,
            None => return None,
        };
        // The actual equation we want to represent is:
        // r' = -p' / (t p^2)
        // We can do a trick to return a positive-only version and
        // indicate that it should be negative in the fn name.
        Some(price_derivative / (annualized_time * price.pow(fixed!(2e18))))
    }

    /// The derivative of the price after a long.
    ///
    /// The price after a long that moves shares by $\Delta z$ and bonds by $\Delta y$
    /// is equal to $P(\Delta z) = \frac{\mu (z_e + \Delta z)}{y - \Delta y}^T$,
    /// where $T$ is the time stretch constant and $z_e$ is the initial effective share reserves.
    /// Equivalently, for some amount of `delta_base`$= x$ provided to open a long,
    /// we can write:
    ///
    /// $$
    /// p(x) = \frac{\mu (z_e + \frac{x}{c} - g(x) - \zeta)}{y_0 - Y(x)}^{T}
    /// $$
    /// where $g(x)$ is the [open_long_governance_fee](long::fees::open_long_governance_fee),
    /// $Y(x)$ is the [long_amount](long::open::calculate_open_long), and $\zeta$ is the
    /// zeta adjustment.
    ///
    /// To compute the derivative, we first define some auxiliary variables:
    /// $$
    /// a(x) = \mu (z_e + \frac{x}{c} - g(x) - \zeta) \\
    /// b(x) = y_0 - Y(x) \\
    /// v(x) = \frac{a(x)}{b(x)}
    /// $$
    ///
    /// and thus $p(x) = v(x)^T$. Given these, we can write out intermediate derivatives:
    ///
    /// $$
    /// a'(x) = \frac{\mu}{c} - g'(x) \\
    /// b'(x) = -Y'(x) \\
    /// v'(x) = \frac{b a' - a b'}{b^2}
    /// $$
    ///
    /// And finally, the price after long derivative is:
    ///
    /// $$
    /// p'(x) = v'(x) T v(x)^(T-1)
    /// $$
    ///
    fn price_after_long_derivative(
        &self,
        base_amount: FixedPoint,
        bond_amount: FixedPoint,
    ) -> Option<FixedPoint> {
        // g'(x)
        let gov_fee_derivative =
            self.governance_lp_fee() * self.curve_fee() * (fixed!(1e18) - self.get_spot_price());

        // a(x) = u (z_e + x/c - g(x) - zeta)
        let inner_numerator = self.mu()
            * (self.ze() + base_amount / self.vault_share_price()
                - self.open_long_governance_fee(base_amount)
                - self.zeta().into());

        // a'(x) = u / c - g'(x)
        let inner_numerator_derivative = self.mu() / self.vault_share_price() - gov_fee_derivative;

        // b(x) = y_0 - Y(x)
        let inner_denominator = self.bond_reserves() - bond_amount;

        // b'(x) = Y'(x)
        let long_amount_derivative = match self.long_amount_derivative(base_amount) {
            Some(derivative) => derivative,
            None => return None,
        };

        // v(x) = a(x) / b(x)
        // v'(x) = ( b(x) * a'(x) + a(x) * b'(x) ) / b(x)^2
        let inner_derivative = (inner_denominator * inner_numerator_derivative
            + inner_numerator * long_amount_derivative)
            / inner_denominator.pow(fixed!(2e18));

        // p'(x) = v'(x) T v(x)^(T-1)
        // p'(x) = v'(x) T v(x)^(-1)^(1-T)
        // v(x) is flipped to (denominator / numerator) to avoid a negative exponent
        return Some(
            inner_derivative
                * self.time_stretch()
                * (inner_denominator / inner_numerator).pow(fixed!(1e18) - self.time_stretch()),
        );
    }

    /// Calculate the base & bond deltas from the current state given desired new reserve levels.
    ///
    /// Given a target ending pool share reserves, $z_t$, and bond reserves, $y_t$,
    /// the trade deltas to achieve that state would be:
    ///
    /// $$
    /// \Delta x = c * (z_t - z_e) \\
    /// \Delta y = y - y_t - c(\Delta x)
    /// $$
    ///
    /// where $c$ is the vault share price and
    /// $c(\Delta x)$ is the (open_long_curve_fee)[long::fees::open_long_curve_fees].
    fn trade_deltas_from_reserves(
        &self,
        share_reserves: FixedPoint,
        bond_reserves: FixedPoint,
    ) -> (FixedPoint, FixedPoint) {
        let base_delta =
            (share_reserves - self.effective_share_reserves()) * self.vault_share_price();
        let bond_delta =
            (self.bond_reserves() - bond_reserves) - self.open_long_curve_fees(base_delta);
        (base_delta, bond_delta)
    }

    /// Calculates the pool reserve levels to achieve a target interest rate.
    /// This calculation does not take Hyperdrive's solvency constraints or exposure
    /// into account and shouldn't be used directly.
    ///
    /// The price for a given fixed-rate is given by $p = 1 / (r t + 1)$, where
    /// $r$ is the fixed-rate and $t$ is the annualized position duration. The
    /// price for a given pool reserves is given by $p = \frac{\mu z}{y}^T$,
    /// where $\mu$ is the initial share price and $T$ is the time stretch
    /// constant. By setting these equal we can solve for the pool reserve levels
    /// as a function of a target rate.
    ///
    /// For some target rate, $r_t$, the pool share reserves, $z_t$, must be:
    ///
    /// $$
    /// z_t = \frac{1}{\mu} \left(
    ///   \frac{k}{\frac{c}{\mu} + \left(
    ///     (r_t t + 1)^{\frac{1}{T}}
    ///   \right)^{1 - T}}
    /// \right)^{\tfrac{1}{1 - T}}
    /// $$
    ///
    /// and the pool bond reserves, $y_t$, must be:
    ///
    /// $$
    /// y_t = \left(
    ///   \frac{k}{ \frac{c}{\mu} +  \left(
    ///     \left( r_t t + 1 \right)^{\frac{1}{T}}
    ///   \right)^{1-T}}
    /// \right)^{1-T} \left( r_t t + 1 \right)^{\frac{1}{T}}
    /// $$
    fn reserves_given_rate_ignoring_exposure<F: Into<FixedPoint>>(
        &self,
        target_rate: F,
    ) -> (FixedPoint, FixedPoint) {
        let target_rate = target_rate.into();
        let annualized_time =
            self.position_duration() / FixedPoint::from(U256::from(60 * 60 * 24 * 365));

        // First get the target share reserves
        let c_over_mu = self
            .vault_share_price()
            .div_up(self.initial_vault_share_price());
        let scaled_rate = (target_rate.mul_up(annualized_time) + fixed!(1e18))
            .pow(fixed!(1e18) / self.time_stretch());
        let target_base_reserves = (self.k_down()
            / (c_over_mu + scaled_rate.pow(fixed!(1e18) - self.time_stretch())))
        .pow(fixed!(1e18) / (fixed!(1e18) - self.time_stretch()));
        let target_share_reserves = target_base_reserves / self.initial_vault_share_price();

        // Then get the target bond reserves.
        let target_bond_reserves = target_base_reserves * scaled_rate;

        (target_share_reserves, target_bond_reserves)
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
    async fn test_get_targeted_long_with_budget() -> Result<()> {
        // Spawn a test chain and create two agents -- Alice and Bob.
        // Alice is funded with a large amount of capital so that she can initialize
        // the pool. Bob is funded with a random amount of capital so that we
        // can test `get_targeted_long` when budget is the primary constraint
        // and when it is not.

        let allowable_solvency_error = fixed!(1e5);
        let allowable_budget_error = fixed!(1e5);
        let allowable_rate_error = fixed!(1e10);
        let num_newton_iters = 3;

        // Initialize a test chain; don't need mocks because we want state updates.
        let chain = TestChain::new(2).await?;

        // Grab accounts for Alice and Bob.
        let (alice, bob) = (chain.accounts()[0].clone(), chain.accounts()[1].clone());

        // Initialize Alice and Bob as Agents.
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
            let targeted_long = bob
                .get_targeted_long(
                    target_rate,
                    Some(num_newton_iters),
                    Some(allowable_rate_error),
                )
                .await?;
            bob.open_long(targeted_long, None, None).await?;

            // Three things should be true after opening the long:
            //
            // 1. The pool's spot price is under the max spot price prior to
            //    considering fees
            // 2. The pool's solvency is above zero.
            // 3. IF Bob's budget is not consumed; then new rate is close to the target rate

            // Check that our resulting price is under the max
            let spot_price_after_long = bob.get_state().await?.get_spot_price();
            assert!(
                max_spot_price_before_long > spot_price_after_long,
                "Resulting price is greater than the max."
            );

            // Check solvency
            let is_solvent = {
                let state = bob.get_state().await?;
                state.get_solvency() > allowable_solvency_error
            };
            assert!(is_solvent, "Resulting pool state is not solvent.");

            // If the budget was NOT consumed, then we assume the target was hit.
            let new_rate = bob.get_state().await?.get_spot_rate();
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

            // Else, we should have undershot,
            // or by some coincidence the budget was the perfect amount
            // and we hit the rate exactly.
            } else {
                assert!(
                    new_rate <= target_rate,
                    "The new_rate={} should be <= target_rate={} when budget constrained.",
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
