use std::cmp::min;

use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

use super::State;
use crate::yield_space::{Asset, State as YieldSpaceState};

impl State {
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

    // FIXME: Document this.
    fn max_long(&self, maybe_max_iterations: Option<usize>) -> FixedPoint {
        // FIXME: These are the steps of the computation.
        //
        // 1. [ ] Get the maximum buy that is possible on the YieldSpace curve.
        // 2. [ ] If the maximum buy satisfies our solvency checks, then we're
        //       done. If not, then we need to solve for the maximum trade size
        //       iteratively.
        // 3. [ ] Solve for the maximum trade size using Newton's method.

        // FIXME: Document this.
        //
        // From this, we have the max amount of base that can be paid for long.
        // We need to reduce the long amount by the curve fee.
        let (max_base_amount, max_bond_amount) = {
            let (share_amount, mut bond_amount) =
                YieldSpaceState::from(self).get_max_buy(self.time_stretch());
            let base_amount = self.share_price() * share_amount;
            bond_amount -= self.long_curve_fee(base_amount);
            (base_amount, bond_amount)
        };
        if self.solvency(max_base_amount, max_bond_amount).is_some() {
            return max_base_amount;
        }

        // FIXME: Newton's method.
        //
        // 1. [ ] We'll start with a guess of 0, but we'll get smarter later.
        let mut max_base_amount = fixed!(1e18);
        for _ in 0..maybe_max_iterations.unwrap_or(7) {
            // FIXME: We need a function that gives us the bond amount for a
            // base amount. This is the result of the yield space calculation
            // minus the curve fee.
            max_base_amount = max_base_amount
                + self
                    .solvency(max_base_amount, self.long_amount(max_base_amount))
                    .unwrap() // FIXME: Make sure this is safe.
                    / self.solvency_derivative(max_base_amount, self.long_amount(max_base_amount));
        }

        max_base_amount
    }

    // FIXME: Document this.
    fn solvency(&self, base_amount: FixedPoint, bond_amount: FixedPoint) -> Option<FixedPoint> {
        let lhs =
            self.share_reserves() + base_amount.mul_div_down(fixed!(2e18), self.share_price());
        let rhs = (self.long_exposure() / self.share_price())
            + bond_amount.mul_div_down(fixed!(2e18), self.share_price())
            + self.minimum_share_reserves();
        if lhs > rhs {
            Some(lhs - rhs)
        } else {
            None
        }
    }

    // FIXME: Document this.
    //
    // FIXME: This is actually the negation of the derivative.
    fn solvency_derivative(&self, base_amount: FixedPoint, bond_amount: FixedPoint) -> FixedPoint {
        (self.long_amount_derivative(base_amount) - fixed!(1e18))
            .mul_div_down(fixed!(2e18), self.share_price())
    }

    // FIXME: Change this name.
    fn long_amount(&self, base_amount: FixedPoint) -> FixedPoint {
        let long_amount = YieldSpaceState::from(self).get_out_for_in(
            Asset::Shares(base_amount / self.share_price()),
            self.time_stretch(),
        );
        long_amount - self.long_curve_fee(base_amount)
    }

    // FIXME: Document this.
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

    // FIXME: Change this name.
    fn long_curve_fee(&self, base_amount: FixedPoint) -> FixedPoint {
        self.curve_fee() * ((fixed!(1e18) / self.get_spot_price()) - fixed!(1e18)) * base_amount
    }
}

#[cfg(test)]
mod tests {
    use eyre::Result;
    use test_utils::{
        agent::Agent,
        chain::{Chain, TestChain},
    };

    use super::*;

    // FIXME: Make this a fuzz test that fuzzes over random parameters.
    #[tokio::test]
    async fn test_get_max_long() -> Result<()> {
        // Set up the logger.
        tracing_subscriber::fmt::init();

        // Spawn a test chain and create two agents -- Alice and Bob. Alice
        // is funded with a large amount of capital so that she can initialize
        // the pool. Bob is funded with a small amount of capital so that we
        // can test `get_max_short` when budget is the primary constraint.
        let chain = TestChain::new(2).await?;
        let (alice, bob) = (chain.accounts()[0].clone(), chain.accounts()[1].clone());
        let mut alice =
            Agent::new(chain.client(alice).await?, chain.addresses().clone(), None).await?;
        let mut bob = Agent::new(chain.client(bob).await?, chain.addresses(), None).await?;

        let fixed_rate = fixed!(0.2e18);
        let contribution = fixed!(100_000_000e18);
        let budget = fixed!(500_000_000e18);
        alice.fund(contribution).await?;
        bob.fund(budget).await?;

        // Alice initializes the pool.
        alice.initialize(fixed_rate, contribution).await?;

        // Bob opens a max long.
        let max_long = bob.get_max_long(None).await?;
        println!("max long = {}", max_long);
        bob.open_long(max_long).await?;

        Ok(())
    }
}
