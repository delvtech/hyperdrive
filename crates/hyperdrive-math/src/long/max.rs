use ethers::types::I256;
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, int256};

use crate::{State, YieldSpace};

impl State {
    /// Gets the pool's max spot price.
    ///
    /// Hyperdrive has assertions to ensure that traders don't purchase bonds at
    /// negative interest rates. The maximum spot price that longs can push the
    /// market to is given by:
    ///
    /// $$
    /// p_max = \frac{1 - \phi_f}{1 + \phi_c * \left( p_0^{-1} - 1 \right) * \left( \phi_f - 1 \right)}
    /// $$
    pub fn get_max_spot_price(&self) -> FixedPoint {
        (fixed!(1e18) - self.flat_fee())
            / (fixed!(1e18)
                + self
                    .curve_fee()
                    .mul_up(fixed!(1e18).div_up(self.get_spot_price()) - fixed!(1e18)))
            .mul_up(fixed!(1e18) - self.flat_fee())
    }

    /// Gets the pool's solvency.
    pub fn get_solvency(&self) -> FixedPoint {
        self.share_reserves()
            - self.long_exposure() / self.vault_share_price()
            - self.minimum_share_reserves()
    }

    /// Gets the max long that can be opened given a budget.
    ///
    /// We start by calculating the long that brings the pool's spot price to 1.
    /// If we are solvent at this point, then we're done. Otherwise, we approach
    /// the max long iteratively using Newton's method.
    pub fn get_max_long<F: Into<FixedPoint>, I: Into<I256>>(
        &self,
        budget: F,
        checkpoint_exposure: I,
        maybe_max_iterations: Option<usize>,
    ) -> FixedPoint {
        let budget = budget.into();
        let checkpoint_exposure = checkpoint_exposure.into();

        // Get the maximum long that brings the spot price to 1. If the pool is
        // solvent after opening this long, then we're done.
        let (absolute_max_base_amount, absolute_max_bond_amount) = self.absolute_max_long();
        if self
            .solvency_after_long(
                absolute_max_base_amount,
                absolute_max_bond_amount,
                checkpoint_exposure,
            )
            .is_some()
        {
            return absolute_max_base_amount.min(budget);
        }

        // Use Newton's method to iteratively approach a solution. We use pool's
        // solvency $S(x)$ as our objective function, which will converge to the
        // amount of base that needs to be paid to open the maximum long. The
        // derivative of $S(x)$ is negative (since solvency decreases as more
        // longs are opened). The fixed point library doesn't support negative
        // numbers, so we use the negation of the derivative to side-step the
        // issue.
        //
        // Given the current guess of $x_n$, Newton's method gives us an updated
        // guess of $x_{n+1}$:
        //
        // $$
        // x_{n+1} = x_n - \tfrac{S(x_n)}{S'(x_n)} = x_n + \tfrac{S(x_n)}{-S'(x_n)}
        // $$
        //
        // The guess that we make is very important in determining how quickly
        // we converge to the solution.
        let mut max_base_amount =
            self.max_long_guess(absolute_max_base_amount, checkpoint_exposure);
        let mut maybe_solvency = self.solvency_after_long(
            max_base_amount,
            self.calculate_open_long(max_base_amount),
            checkpoint_exposure,
        );
        if maybe_solvency.is_none() {
            panic!("Initial guess in `get_max_long` is insolvent.");
        }
        let mut solvency = maybe_solvency.unwrap();
        for _ in 0..maybe_max_iterations.unwrap_or(7) {
            // If the max base amount is equal to or exceeds the absolute max,
            // we've gone too far and the calculation deviated from reality at
            // some point.
            if max_base_amount >= absolute_max_base_amount {
                panic!("Reached absolute max bond amount in `get_max_long`.");
            }

            // If the max base amount exceeds the budget, we know that the
            // entire budget can be consumed without running into solvency
            // constraints.
            if max_base_amount >= budget {
                return budget;
            }

            // TODO: It may be better to gracefully handle crossing over the
            // root by extending the fixed point math library to handle negative
            // numbers or even just using an if-statement to handle the negative
            // numbers.
            //
            // Proceed to the next step of Newton's method. Once we have a
            // candidate solution, we check to see if the pool is solvent if
            // a long is opened with the candidate amount. If the pool isn't
            // solvent, then we're done.
            let maybe_derivative = self.solvency_after_long_derivative(max_base_amount);
            if maybe_derivative.is_none() {
                break;
            }
            let possible_max_base_amount = max_base_amount + solvency / maybe_derivative.unwrap();
            maybe_solvency = self.solvency_after_long(
                possible_max_base_amount,
                self.calculate_open_long(possible_max_base_amount),
                checkpoint_exposure,
            );
            if let Some(s) = maybe_solvency {
                solvency = s;
                max_base_amount = possible_max_base_amount;
            } else {
                break;
            }
        }

        // Ensure that the final result is less than the absolute max and clamp
        // to the budget.
        if max_base_amount >= absolute_max_base_amount {
            panic!("Reached absolute max bond amount in `get_max_long`.");
        }
        if max_base_amount >= budget {
            return budget;
        }

        max_base_amount
    }

    /// Calculates the largest long that can be opened without buying bonds at a
    /// negative interest rate. This calculation does not take Hyperdrive's
    /// solvency constraints into account and shouldn't be used directly.
    fn absolute_max_long(&self) -> (FixedPoint, FixedPoint) {
        // We are targeting the pool's max spot price of:
        //
        // p_max = (1 - flatFee) / (1 + curveFee * (1 / p_0 - 1) * (1 - flatFee))
        //
        // We can derive a formula for the target bond reserves y_t in
        // terms of the target share reserves z_t as follows:
        //
        // p_max = ((mu * z_t) / y_t) ** t_s
        //
        //                       =>
        //
        // y_t = (mu * z_t) * ((1 + curveFee * (1 / p_0 - 1) * (1 - flatFee)) / (1 - flatFee)) ** (1 / t_s)
        //
        // We can use this formula to solve our YieldSpace invariant for z_t:
        //
        // k = (c / mu) * (mu * z_t) ** (1 - t_s) +
        //     (
        //         (mu * z_t) * ((1 + curveFee * (1 / p_0 - 1) * (1 - flatFee)) / (1 - flatFee)) ** (1 / t_s)
        //     ) ** (1 - t_s)
        //
        //                       =>
        //
        // z_t = (1 / mu) * (
        //           k / (
        //               (c / mu) +
        //               ((1 + curveFee * (1 / p_0 - 1) * (1 - flatFee)) / (1 - flatFee)) ** ((1 - t_s) / t_s))
        //           )
        //       ) ** (1 / (1 - t_s))
        let inner = (self.k_down()
            / (self
                .vault_share_price()
                .div_up(self.initial_vault_share_price())
                + ((fixed!(1e18)
                    + self
                        .curve_fee()
                        .mul_up(fixed!(1e18).div_up(self.get_spot_price()) - fixed!(1e18))
                        .mul_up(fixed!(1e18) - self.flat_fee()))
                .div_up(fixed!(1e18) - self.flat_fee()))
                .pow((fixed!(1e18) - self.time_stretch()) / (self.time_stretch()))))
        .pow(fixed!(1e18) / (fixed!(1e18) - self.time_stretch()));
        let target_share_reserves = inner / self.initial_vault_share_price();

        // Now that we have the target share reserves, we can calculate the
        // target bond reserves using the formula:
        //
        // y_t = (mu * z_t) * ((1 + curveFee * (1 / p_0 - 1) * (1 - flatFee)) / (1 - flatFee)) ** (1 / t_s)
        //
        // `inner` as defined above is `mu * z_t` so we calculate y_t as
        //
        // y_t = inner * ((1 + curveFee * (1 / p_0 - 1) * (1 - flatFee)) / (1 - flatFee)) ** (1 / t_s)
        let target_bond_reserves = inner
            * ((fixed!(1e18)
                + self.curve_fee()
                    * (fixed!(1e18) / (self.get_spot_price()) - fixed!(1e18))
                    * (fixed!(1e18) - self.flat_fee()))
                / (fixed!(1e18) - self.flat_fee()))
            .pow(fixed!(1e18).div_up(self.time_stretch()));

        // The absolute max base amount is given by:
        //
        // absoluteMaxBaseAmount = c * (z_t - z)
        let absolute_max_base_amount =
            (target_share_reserves - self.effective_share_reserves()) * self.vault_share_price();

        // The absolute max bond amount is given by:
        //
        // absoluteMaxBondAmount = (y - y_t) - c(x)
        let absolute_max_bond_amount = (self.bond_reserves() - target_bond_reserves)
            - self.open_long_curve_fees(absolute_max_base_amount);

        (absolute_max_base_amount, absolute_max_bond_amount)
    }

    /// Gets an initial guess of the max long that can be opened. This is a
    /// reasonable estimate that is guaranteed to be less than the true max
    /// long. We use this to get a reasonable starting point for Newton's
    /// method.
    fn max_long_guess(
        &self,
        absolute_max_base_amount: FixedPoint,
        checkpoint_exposure: I256,
    ) -> FixedPoint {
        // Get an initial estimate of the max long by using the spot price as
        // our conservative price.
        let spot_price = self.get_spot_price();
        let guess = self.max_long_estimate(spot_price, spot_price, checkpoint_exposure);

        // We know that the spot price is 1 when the absolute max base amount is
        // used to open a long. We also know that our spot price isn't a great
        // estimate (conservative or otherwise) of the realized price that the
        // max long will pay, so we calculate a better estimate of the realized
        // price by interpolating between the spot price and 1 depending on how
        // large the estimate is.
        let t = (guess / absolute_max_base_amount)
            .pow(fixed!(1e18).div_up(fixed!(1e18) - self.time_stretch()))
            * fixed!(0.8e18);
        let estimate_price = spot_price * (fixed!(1e18) - t) + fixed!(1e18) * t;

        // Recalculate our intial guess using the bootstrapped conservative
        // estimate of the realized price.
        self.max_long_estimate(estimate_price, spot_price, checkpoint_exposure)
    }

    /// Estimates the max long based on the pool's current solvency and a
    /// conservative price estimate, $p_r$.
    ///
    /// We can use our estimate price $p_r$ to approximate $y(x)$ as
    /// $y(x) \approx p_r^{-1} \cdot x - c(x)$. Plugging this into our
    /// solvency function $s(x)$, we can calculate the share reserves and
    /// exposure after opening a long with $x$ base as:
    ///
    /// \begin{aligned}
    /// z(x) &= z_0 + \tfrac{x - g(x)}{c} - z_{min} \\
    /// e(x) &= e_0 + min(exposure_{c}, 0) + 2 \cdot y(x) - x + g(x) \\
    ///      &= e_0 + min(exposure_{c}, 0) + 2 \cdot p_r^{-1} \cdot x -
    ///             2 \cdot c(x) - x + g(x)
    /// \end{aligned}
    ///
    /// We debit and negative checkpoint exposure from $e_0$ since the
    /// global exposure doesn't take into account the negative exposure
    /// from non-netted shorts in the checkpoint. These forumulas allow us
    /// to calculate the approximate ending solvency of:
    ///
    /// $$
    /// s(x) \approx z(x) - \tfrac{e(x)}{c} - z_{min}
    /// $$
    ///
    /// If we let the initial solvency be given by $s_0$, we can solve for
    /// $x$ as:
    ///
    /// $$
    /// x = \frac{c}{2} \cdot \frac{s_0 + min(exposure_{c}, 0)}{
    ///         p_r^{-1} +
    ///         \phi_{g} \cdot \phi_{c} \cdot \left( 1 - p \right) -
    ///         1 -
    ///         \phi_{c} \cdot \left( p^{-1} - 1 \right)
    ///     }
    /// $$
    fn max_long_estimate(
        &self,
        estimate_price: FixedPoint,
        spot_price: FixedPoint,
        checkpoint_exposure: I256,
    ) -> FixedPoint {
        let checkpoint_exposure = FixedPoint::from(-checkpoint_exposure.min(int256!(0)));
        let mut estimate = self.get_solvency() + checkpoint_exposure / self.vault_share_price();
        estimate = estimate.mul_div_down(self.vault_share_price(), fixed!(2e18));
        estimate /= fixed!(1e18) / estimate_price
            + self.governance_lp_fee() * self.curve_fee() * (fixed!(1e18) - spot_price)
            - fixed!(1e18)
            - self.curve_fee() * (fixed!(1e18) / spot_price - fixed!(1e18));
        estimate
    }

    /// Gets the solvency of the pool $S(x)$ after a long is opened with a base
    /// amount $x$.
    ///
    /// Since longs can net out with shorts in this checkpoint, we decrease
    /// the global exposure variable by any negative exposure we have
    /// in the checkpoint. The pool's solvency is calculated as:
    ///
    /// $$
    /// s = z - \tfrac{exposure + min(exposure_{checkpoint}, 0)}{c} - z_{min}
    /// $$
    ///
    /// When a long is opened, the share reserves $z$ increase by:
    ///
    /// $$
    /// \Delta z = \tfrac{x - g(x)}{c}
    /// $$
    ///
    /// Opening the long increases the non-netted longs by the bond amount. From
    /// this, the change in the exposure is given by:
    ///
    /// $$
    /// \Delta exposure = y(x)
    /// $$
    ///
    /// From this, we can calculate $S(x)$ as:
    ///
    /// $$
    /// S(x) = \left( z + \Delta z \right) - \left(
    ///            \tfrac{exposure + min(exposure_{checkpoint}, 0) + \Delta exposure}{c}
    ///        \right) - z_{min}
    /// $$
    ///
    /// It's possible that the pool is insolvent after opening a long. In this
    /// case, we return `None` since the fixed point library can't represent
    /// negative numbers.
    fn solvency_after_long(
        &self,
        base_amount: FixedPoint,
        bond_amount: FixedPoint,
        checkpoint_exposure: I256,
    ) -> Option<FixedPoint> {
        let governance_fee = self.open_long_governance_fee(base_amount);
        let share_reserves = self.share_reserves() + base_amount / self.vault_share_price()
            - governance_fee / self.vault_share_price();
        let exposure = self.long_exposure() + bond_amount;
        let checkpoint_exposure = FixedPoint::from(-checkpoint_exposure.min(int256!(0)));
        if share_reserves + checkpoint_exposure / self.vault_share_price()
            >= exposure / self.vault_share_price() + self.minimum_share_reserves()
        {
            Some(
                share_reserves + checkpoint_exposure / self.vault_share_price()
                    - exposure / self.vault_share_price()
                    - self.minimum_share_reserves(),
            )
        } else {
            None
        }
    }

    /// Gets the negation of the derivative of the pool's solvency with respect
    /// to the base amount that the long pays.
    ///
    /// The derivative of the pool's solvency $S(x)$ with respect to the base
    /// amount that the long pays is given by:
    ///
    /// $$
    /// S'(x) = \tfrac{1}{c} \cdot \left( 1 - y'(x) - \phi_{g} \cdot p \cdot c'(x) \right) \\
    ///       = \tfrac{1}{c} \cdot \left(
    ///             1 - y'(x) - \phi_{g} \cdot \phi_{c} \cdot \left( 1 - p \right)
    ///         \right)
    /// $$
    ///
    /// This derivative is negative since solvency decreases as more longs are
    /// opened. We use the negation of the derivative to stay in the positive
    /// domain, which allows us to use the fixed point library.
    fn solvency_after_long_derivative(&self, base_amount: FixedPoint) -> Option<FixedPoint> {
        let maybe_derivative = self.long_amount_derivative(base_amount);
        maybe_derivative.map(|derivative| {
            (derivative
                + self.governance_lp_fee()
                    * self.curve_fee()
                    * (fixed!(1e18) - self.get_spot_price())
                - fixed!(1e18))
            .mul_div_down(fixed!(1e18), self.vault_share_price())
        })
    }

    /// Gets the derivative of [long_amount](long_amount) with respect to the
    /// base amount.
    ///
    /// We calculate the derivative of the long amount $y(x)$ as:
    ///
    /// $$
    /// y'(x) = y_{*}'(x) - c'(x)
    /// $$
    ///
    /// Where $y_{*}'(x)$ is the derivative of $y_{*}(x)$ and $c'(x)$ is the
    /// derivative of [$c(x)$](long_curve_fee). $y_{*}'(x)$ is given by:
    ///
    /// $$
    /// y_{*}'(x) = \left( \mu \cdot (z + \tfrac{x}{c}) \right)^{-t_s}
    ///             \left(
    ///                 k - \tfrac{c}{\mu} \cdot
    ///                 \left(
    ///                     \mu \cdot (z + \tfrac{x}{c}
    ///                 \right)^{1 - t_s}
    ///             \right)^{\tfrac{t_s}{1 - t_s}}
    /// $$
    ///
    /// and $c'(x)$ is given by:
    ///
    /// $$
    /// c'(x) = \phi_{c} \cdot \left( \tfrac{1}{p} - 1 \right)
    /// $$
    fn long_amount_derivative(&self, base_amount: FixedPoint) -> Option<FixedPoint> {
        let share_amount = base_amount / self.vault_share_price();
        let inner =
            self.initial_vault_share_price() * (self.effective_share_reserves() + share_amount);
        let mut derivative = fixed!(1e18) / (inner).pow(self.time_stretch());

        // It's possible that k is slightly larger than the rhs in the inner
        // calculation. If this happens, we are close to the root, and we short
        // circuit.
        let k = self.k_down();
        let rhs = self.vault_share_price().mul_div_down(
            inner.pow(self.time_stretch()),
            self.initial_vault_share_price(),
        );
        if k < rhs {
            return None;
        }
        derivative *= (k - rhs).pow(
            self.time_stretch()
                .div_up(fixed!(1e18) - self.time_stretch()),
        );

        // Finish computing the derivative.
        derivative -= self.curve_fee() * ((fixed!(1e18) / self.get_spot_price()) - fixed!(1e18));

        Some(derivative)
    }
}

#[cfg(test)]
mod tests {
    use std::panic;

    use ethers::types::U256;
    use eyre::Result;
    use fixed_point_macros::uint256;
    use hyperdrive_wrappers::wrappers::mock_hyperdrive_math::MaxTradeParams;
    use rand::{thread_rng, Rng};
    use test_utils::{
        agent::Agent,
        chain::{Chain, TestChain, TestChainWithMocks},
        constants::{FAST_FUZZ_RUNS, FUZZ_RUNS},
    };
    use tracing_test::traced_test;

    use super::*;
    use crate::get_effective_share_reserves;

    /// This test differentially fuzzes the `absolute_max_long` function against
    /// the Solidity analogue `calculateAbsoluteMaxLong`.
    #[tokio::test]
    async fn fuzz_absolute_max_long() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_hyperdrive_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let actual = panic::catch_unwind(|| state.absolute_max_long());
            match mock
                .calculate_absolute_max_long(
                    MaxTradeParams {
                        share_reserves: state.info.share_reserves,
                        bond_reserves: state.info.bond_reserves,
                        longs_outstanding: state.info.longs_outstanding,
                        long_exposure: state.info.long_exposure,
                        share_adjustment: state.info.share_adjustment,
                        time_stretch: state.config.time_stretch,
                        vault_share_price: state.info.vault_share_price,
                        initial_vault_share_price: state.config.initial_vault_share_price,
                        minimum_share_reserves: state.config.minimum_share_reserves,
                        curve_fee: state.config.fees.curve,
                        flat_fee: state.config.fees.flat,
                        governance_lp_fee: state.config.fees.governance_lp,
                    },
                    get_effective_share_reserves(
                        state.info.share_reserves.into(),
                        state.info.share_adjustment,
                    )
                    .into(),
                    state.get_spot_price().into(),
                )
                .call()
                .await
            {
                Ok((expected_base_amount, expected_bond_amount)) => {
                    let (actual_base_amount, actual_bond_amount) = actual.unwrap();
                    assert_eq!(actual_base_amount, FixedPoint::from(expected_base_amount));
                    assert_eq!(actual_bond_amount, FixedPoint::from(expected_bond_amount));
                }
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }

    /// This test differentially fuzzes the `get_max_long` function against the
    /// Solidity analogue `calculateMaxLong`. `calculateMaxLong` doesn't take
    /// a trader's budget into account, so it only provides a subset of
    /// `get_max_long`'s functionality. With this in mind, we provide
    /// `get_max_long` with a budget of `U256::MAX` to ensure that the two
    /// functions are equivalent.
    #[tokio::test]
    async fn fuzz_get_max_long() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_hyperdrive_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let checkpoint_exposure = {
                let value = rng.gen_range(fixed!(0)..=FixedPoint::from(I256::MAX));
                let sign = rng.gen::<bool>();
                if sign {
                    -I256::try_from(value).unwrap()
                } else {
                    I256::try_from(value).unwrap()
                }
            };
            let actual =
                panic::catch_unwind(|| state.get_max_long(U256::MAX, checkpoint_exposure, None));
            match mock
                .calculate_max_long(
                    MaxTradeParams {
                        share_reserves: state.info.share_reserves,
                        bond_reserves: state.info.bond_reserves,
                        longs_outstanding: state.info.longs_outstanding,
                        long_exposure: state.info.long_exposure,
                        share_adjustment: state.info.share_adjustment,
                        time_stretch: state.config.time_stretch,
                        vault_share_price: state.info.vault_share_price,
                        initial_vault_share_price: state.config.initial_vault_share_price,
                        minimum_share_reserves: state.config.minimum_share_reserves,
                        curve_fee: state.config.fees.curve,
                        flat_fee: state.config.fees.flat,
                        governance_lp_fee: state.config.fees.governance_lp,
                    },
                    checkpoint_exposure,
                    uint256!(7),
                )
                .call()
                .await
            {
                Ok((expected_base_amount, ..)) => {
                    assert_eq!(actual.unwrap(), FixedPoint::from(expected_base_amount));
                }
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }

    #[traced_test]
    #[tokio::test]
    async fn test_get_max_long() -> Result<()> {
        // Spawn a test chain and create two agents -- Alice and Bob. Alice
        // is funded with a large amount of capital so that she can initialize
        // the pool. Bob is funded with a small amount of capital so that we
        // can test `get_max_short` when budget is the primary constraint.
        let mut rng = thread_rng();
        let chain = TestChain::new(2).await?;
        let (alice, bob) = (chain.accounts()[0].clone(), chain.accounts()[1].clone());
        let mut alice =
            Agent::new(chain.client(alice).await?, chain.addresses().clone(), None).await?;
        let mut bob = Agent::new(chain.client(bob).await?, chain.addresses(), None).await?;
        let config = bob.get_config().clone();

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

            // Bob opens a max long.
            let max_spot_price = bob.get_state().await?.get_max_spot_price();
            let max_long = bob.get_max_long(None).await?;
            let spot_price_after_long = bob.get_state().await?.get_spot_price_after_long(max_long);
            bob.open_long(max_long, None, None).await?;

            // One of three things should be true after opening the long:
            //
            // 1. The pool's spot price reached the max spot price prior to
            //    considering fees.
            // 2. The pool's solvency is close to zero.
            // 3. Bob's budget is consumed.
            let is_max_price =
                max_spot_price - spot_price_after_long.min(max_spot_price) < fixed!(1e15);
            let is_solvency_consumed = {
                let state = bob.get_state().await?;
                let error_tolerance = fixed!(1_000e18).mul_div_down(fixed_rate, fixed!(0.1e18));
                state.get_solvency() < error_tolerance
            };
            let is_budget_consumed = {
                let error_tolerance = fixed!(1e18);
                bob.base() < error_tolerance
            };
            assert!(
                is_max_price || is_solvency_consumed || is_budget_consumed,
                "Invalid max long."
            );

            // Revert to the snapshot and reset the agent's wallets.
            chain.revert(id).await?;
            alice.reset(Default::default());
            bob.reset(Default::default());
        }

        Ok(())
    }
}
