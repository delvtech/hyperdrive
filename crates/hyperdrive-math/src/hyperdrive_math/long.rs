use std::cmp::min;

use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

use super::State;
use crate::yield_space::{Asset, State as YieldSpaceState};

impl State {
    /// Gets the pool's solvency.
    pub fn get_solvency(&self) -> FixedPoint {
        self.share_reserves()
            - self.long_exposure() / self.share_price()
            - self.minimum_share_reserves()
    }

    /// Gets the long amount that will be opened for a given base amount.
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
    pub fn get_long_amount(&self, base_amount: FixedPoint) -> FixedPoint {
        let long_amount = YieldSpaceState::from(self).get_out_for_in(
            Asset::Shares(base_amount / self.share_price()),
            self.time_stretch(),
        );
        long_amount - self.long_curve_fee(base_amount)
    }

    /// Gets the max long that can be opened.
    ///
    /// Iteratively calculates the max long that can be opened on the pool.
    /// The number of iterations can be configured with `max_iterations`, which
    /// defaults to 7 if it is passed as `None`.
    pub fn get_max_long(
        &self,
        budget: FixedPoint,
        maybe_max_iterations: Option<usize>,
    ) -> FixedPoint {
        // Get the maximum long that can be opened.
        let max_base_amount = self.max_long(maybe_max_iterations);

        // If the maximum long that can be opened is less than the budget, then
        // we return the maximum long that can be opened. Otherwise, we return
        // the budget.
        min(max_base_amount, budget)
    }

    // FIXME: Short circuit when the max base amount exceeds the budget. If we
    // do this, we can just make this the `get_max_long` function.
    //
    /// Gets the max long that can be opened irrespective of budget.
    ///
    /// We start by calculating the long that brings the pool's spot price to 1.
    /// If we are solvent at this point, then we're done. Otherwise, we approach
    /// the max long iteratively using Newton's method.
    fn max_long(&self, maybe_max_iterations: Option<usize>) -> FixedPoint {
        // Get the maximum long that brings the spot price to 1. If the pool is
        // solvent after opening this long, then we're done.
        let (mut max_base_amount, max_bond_amount) = {
            let (share_amount, mut bond_amount) =
                YieldSpaceState::from(self).get_max_buy(self.time_stretch());
            let base_amount = self.share_price() * share_amount;
            bond_amount -= self.long_curve_fee(base_amount);
            (base_amount, bond_amount)
        };
        if self.solvency(max_base_amount, max_bond_amount).is_some() {
            return max_base_amount;
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
        max_base_amount = fixed!(1e18);
        for _ in 0..maybe_max_iterations.unwrap_or(7) {
            max_base_amount = max_base_amount
                + self
                    .solvency(max_base_amount, self.get_long_amount(max_base_amount))
                    .unwrap()
                    / self.solvency_derivative(max_base_amount);
        }

        max_base_amount
    }

    /// Gets the solvency of the pool $S(x)$ after a long is opened with a base
    /// amount $x$.
    ///
    /// The pool's solvency is calculated as:
    ///
    /// $$
    /// s = z - \tfrac{exposure}{c} - z_{min}
    /// $$
    ///
    /// When a long is opened, the share reserves $z$ increase by:
    ///
    /// $$
    /// \Delta z = \tfrac{x - g(x)}{c}
    /// $$
    ///
    /// In the solidity implementation, we calculate the delta in the exposure
    /// as:
    ///
    /// ```
    /// uint128 longExposureDelta = (2 *
    ///     _bondProceeds -
    ///     _shareReservesDelta.mulDown(_sharePrice)).toUint128();
    /// ```
    ///
    /// where `shareReservesDelta = _shareAmount - governanceCurveFee.divDown(_sharePrice)`.
    /// From this, we can calculate our exposure as:
    ///
    /// $$
    /// \Delta exposure = 2 \cdot y(x) - x + g(x)
    /// $$
    ///
    /// From this, we can calculate $S(x)$ as:
    ///
    /// $$
    /// S(x) = \left( z + \Delta z \right) - \left(
    ///            \tfrac{exposure + \Delta exposure}{c}
    ///        \right) - z_{min}
    /// $$
    ///
    /// It's possible that the pool is insolvent after opening a long. In this
    /// case, we return `None` since the fixed point library can't represent
    /// negative numbers.
    fn solvency(&self, base_amount: FixedPoint, bond_amount: FixedPoint) -> Option<FixedPoint> {
        let governance_fee = self.long_governance_fee(base_amount);
        let share_reserves = self.share_reserves() + base_amount / self.share_price()
            - governance_fee / self.share_price();
        let exposure =
            self.long_exposure() + fixed!(2e18) * bond_amount - base_amount + governance_fee;
        if share_reserves >= exposure / self.share_price() + self.minimum_share_reserves() {
            Some(share_reserves - exposure / self.share_price() - self.minimum_share_reserves())
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
    /// S'(x) = \tfrac{2}{c} \cdot \left( 1 - y'(x) - \phi_{g} \cdot p \cdot c'(x) \right) \\
    ///       = \tfrac{2}{c} \cdot \left(
    ///             1 - y'(x) - \phi_{g} \cdot \phi_{c} \cdot \left( 1 - p \right)
    ///         \right)
    /// $$
    ///
    /// This derivative is negative since solvency decreases as more longs are
    /// opened. We use the negation of the derivative to stay in the positive
    /// domain, which allows us to use the fixed point library.
    fn solvency_derivative(&self, base_amount: FixedPoint) -> FixedPoint {
        (self.long_amount_derivative(base_amount)
            + self.governance_fee() * self.curve_fee() * (fixed!(1e18) - self.get_spot_price())
            - fixed!(1e18))
        .mul_div_down(fixed!(2e18), self.share_price())
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
    fn long_amount_derivative(&self, base_amount: FixedPoint) -> FixedPoint {
        let share_amount = base_amount / self.share_price();
        let inner = self.initial_share_price() * (self.share_reserves() + share_amount);
        let mut derivative = fixed!(1e18) / (inner).pow(self.time_stretch());
        derivative *= (YieldSpaceState::from(self).k(self.time_stretch())
            - (self.share_price() / self.initial_share_price()) * inner.pow(self.time_stretch()))
        .pow(self.time_stretch() / (fixed!(1e18) - self.time_stretch()));
        derivative -= self.curve_fee() * ((fixed!(1e18) / self.get_spot_price()) - fixed!(1e18));

        derivative
    }

    /// Gets the curve fee paid by longs for a given base amount.
    ///
    /// The curve fee $c(x)$ paid by longs is given by:
    ///
    /// $$
    /// c(x) = \phi_{c} \cdot \left( \tfrac{1}{p} - 1 \right) \cdot x
    /// $$
    fn long_curve_fee(&self, base_amount: FixedPoint) -> FixedPoint {
        self.curve_fee() * ((fixed!(1e18) / self.get_spot_price()) - fixed!(1e18)) * base_amount
    }

    /// Gets the governance fee paid by longs for a given base amount.
    ///
    /// Unlike the [curve fee](long_curve_fee) which is paid in bonds, the
    /// governance fee is paid in base. The governance fee $g(x)$ paid by longs
    /// is given by:
    ///
    /// $$
    /// g(x) = \phi_{g} \cdot p \cdot c(x)
    /// $$
    fn long_governance_fee(&self, base_amount: FixedPoint) -> FixedPoint {
        self.governance_fee() * self.get_spot_price() * self.long_curve_fee(base_amount)
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
            alice.initialize(fixed_rate, contribution).await?;

            // Some of the checkpoint passes and variable interest accrues.
            alice.checkpoint(alice.latest_checkpoint().await?).await?;
            let rate = rng.gen_range(fixed!(0)..=fixed!(0.5e18));
            alice
                .advance_time(
                    rate,
                    FixedPoint::from(config.checkpoint_duration) * fixed!(0.5e18),
                )
                .await?;

            // Bob opens a max long.
            let max_long = bob.get_max_long(None).await?;
            bob.open_long(max_long, None).await?;

            // One of three things should be true after opening the long:
            //
            // 1. Bob's budget is consumed.
            // 2. The pool's solvency is close to zero.
            // 3. The pool's spot price is equal to 1.
            let is_max_price = {
                let state = bob.get_state().await?;
                fixed!(1e18) - state.get_spot_price() < fixed!(1e15)
            };
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
