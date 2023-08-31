use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

use super::State;
use crate::yield_space::{Asset, State as YieldSpaceState};

impl State {
    /// Gets the minimum price that the pool can support.
    ///
    /// YieldSpace intersects the y-axis with a finite slope, so there is a
    /// minimum price that the pool can support. This is the price at which the
    /// share reserves are equal to the minimum share reserves.
    ///
    /// We can solve for the bond reserves $y_{max}$ implied by the share reserves
    /// being equal to $z_{min}$ using the current k value:
    ///
    /// $$
    /// k = \tfrac{c}{\mu} \cdot \left( \mu \cdot z_{min} \right)^{1 - t_s} + y_{max}^{1 - t_s} \\
    /// \implies \\
    /// y_{max} = \left( k - \tfrac{c}{\mu} \cdot \left( \mu \cdot z_{min} \right)^{1 - t_s} \right)^{\tfrac{1}{1 - t_s}}
    /// $$
    ///
    /// From there, we can calculate the spot price as normal as:
    ///
    /// $$
    /// p = \left( \tfrac{\mu \cdot z_{min}}{y_{max}} \right)^{t_s}
    /// $$
    pub fn get_min_price(&self) -> FixedPoint {
        let k = YieldSpaceState::from(self).k(self.time_stretch());
        let y_max = (k
            - (self.share_price() / self.initial_share_price())
                * (self.initial_share_price() * self.minimum_share_reserves())
                    .pow(fixed!(1e18) - self.time_stretch()))
        .pow(fixed!(1e18).div_up(fixed!(1e18) - self.time_stretch()));
        ((self.initial_share_price() * self.minimum_share_reserves()) / y_max)
            .pow(self.time_stretch())
    }

    /// Gets the max short that can be opened with the given budget.
    ///
    /// We start by finding the largest possible short (irrespective of budget),
    /// and then we iteratively approach a solution using Newton's method if the
    /// budget isn't satisified.
    ///
    /// The user can provide `maybe_conservative_price`, which is a lower bound
    /// on the realized price that the short will pay. This is used to help the
    /// algorithm converge faster in real world situations. If this is `None`,
    /// then we'll use the theoretical worst case realized price.
    pub fn get_max_short<F1: Into<FixedPoint>, F2: Into<FixedPoint>>(
        &self,
        budget: F1,
        open_share_price: F2,
        maybe_conservative_price: Option<FixedPoint>, // TODO: Is there a nice way of abstracting the inner type?
        maybe_max_iterations: Option<usize>,
    ) -> FixedPoint {
        let budget = budget.into();
        let open_share_price = open_share_price.into();

        // If the budget is zero, then we return early.
        if budget == fixed!(0) {
            return fixed!(0);
        }

        // Get the spot price and the open share price. If the open share price
        // is zero, then we'll use the current share price since the checkpoint
        // hasn't been minted yet.
        let spot_price = self.get_spot_price();
        let open_share_price = if open_share_price != fixed!(0) {
            open_share_price
        } else {
            self.share_price()
        };

        // Assuming the budget is infinite, find the largest possible short that
        // can be opened. If the short satisfies the budget, this is the max
        // short amount.
        let (.., mut max_short_bonds) = self.max_short(spot_price, open_share_price);
        if self.get_short_deposit(max_short_bonds, spot_price, open_share_price) <= budget {
            return max_short_bonds;
        }

        // Use Newton's method to iteratively approach a solution. We use the
        // short deposit in base minus the budget as our objective function,
        // which will converge to the amount of bonds that need to be shorted
        // for the short deposit to consume the entire budget. Using the
        // notation from the function comments, we can write our objective
        // function as:
        //
        // $$
        // F(x) = B - D(x)
        // $$
        //
        // Since $B$ is just a constant, $F'(x) = -D'(x)$. Given the current guess
        // of $x_n$, Newton's method gives us an updated guess of $x_{n+1}$:
        //
        // $$
        // x_{n+1} = x_n - \tfrac{F(x_n)}{F'(x_n)} = x_n + \tfrac{B - D(x_n)}{D'(x_n)}
        // $$
        //
        // The guess that we make is very important in determining how quickly
        // we converge to the solution.
        max_short_bonds = self.max_short_guess(
            budget,
            spot_price,
            open_share_price,
            maybe_conservative_price,
        );
        for _ in 0..maybe_max_iterations.unwrap_or(7) {
            max_short_bonds = max_short_bonds
                + (budget - self.get_short_deposit(max_short_bonds, spot_price, open_share_price))
                    / self.short_deposit_derivative(max_short_bonds, spot_price, open_share_price);
        }

        // Verify that the max short satisfies the budget.
        if budget < self.get_short_deposit(max_short_bonds, spot_price, open_share_price) {
            panic!("max short exceeded budget");
        }

        max_short_bonds
    }

    /// Gets the maximum short that the pool can support. This doesn't take into
    /// account a trader's budget.
    fn max_short(
        &self,
        spot_price: FixedPoint,
        open_share_price: FixedPoint,
    ) -> (FixedPoint, FixedPoint) {
        // Get the share and bond reserves after opening the largest possible
        // short. The minimum share reserves are given by z = y_l/c + z_min, so
        // we can solve for optimal bond reserves directly using the yield space
        // invariant.
        let ts = FixedPoint::from(self.config.time_stretch);
        let k = YieldSpaceState::from(self).k(self.config.time_stretch.into());
        let optimal_share_reserves =
            (self.longs_outstanding() / self.share_price()) + self.minimum_share_reserves();
        let optimal_bond_reserves = (k
            - (self.share_price() / self.initial_share_price())
                * (self.initial_share_price() * optimal_share_reserves).pow(fixed!(1e18) - ts))
        .pow(fixed!(1e18) / (fixed!(1e18) - ts));

        // The maximum short amount is just given by the difference between the
        // optimal bond reserves and the current bond reserves.
        let short_amount = optimal_bond_reserves - self.bond_reserves();
        let base_amount = self.get_short_deposit(short_amount, spot_price, open_share_price);

        (base_amount, short_amount)
    }

    /// Gets an initial guess for the max short calculation.
    ///
    /// The user can specify a conservative price that they know is less than
    /// the worst-case realized price. This significantly improves the speed of
    /// convergence of Newton's method.
    fn max_short_guess(
        &self,
        budget: FixedPoint,
        spot_price: FixedPoint,
        open_share_price: FixedPoint,
        maybe_conservative_price: Option<FixedPoint>,
    ) -> FixedPoint {
        // If a conservative price is given, we can use it to solve for an
        // initial guess for what the max short is. If this conservative price
        // is an overestimate or if a conservative price isn't given, we revert
        // to using the theoretical worst case scenario as our guess.
        if let Some(conservative_price) = maybe_conservative_price {
            // Given our conservative price $p_c$, we can write the short deposit
            // function as:
            //
            // $$
            // D(x) = \left( \tfrac{c}{c_0} - $p_c$ \right) \cdot x
            //        + \phi_{flat} \cdot x + \phi_{curve} \cdot (1 - p) \cdot x
            // $$
            //
            // We then solve for $x^*$ such that $D(x^*) = B$, which gives us a
            // guess of:
            //
            // $$
            // x^* = \tfrac{B}{\tfrac{c}{c_0} - $p_c$ + \phi_{flat} + \phi_{curve} \cdot (1 - p)}
            // $$
            //
            // If the budget can cover the actual short deposit on $x^*$ , we
            // return it as our guess. Otherwise, we revert to the worst case
            // scenario.
            let guess = budget
                / (self.share_price().div_up(open_share_price)
                    + self.flat_fee()
                    + self.curve_fee() * (fixed!(1e18) - spot_price)
                    - conservative_price);
            if budget >= self.get_short_deposit(guess, spot_price, open_share_price) {
                return guess;
            }
        }

        // We know that the max short's bond amount is greater than 0 which
        // gives us an absolute lower bound, but we can do better most of the
        // time. If the fixed rate was infinite, the max loss for shorts would
        // be 1 per bond since the spot price would be 0. With this in mind, the
        // max short amount would be equal to the budget before we consider the
        // flat fee, curve fee, and back-paid interest. Considering that the
        // budget also needs to cover the fees and back-paid interest, we
        // subtract these components from the budget to get a better estimate of
        // the max bond amount. If subtracting these components results in a
        // negative number, we just 0 as our initial guess.
        let worst_case_deposit = self.get_short_deposit(budget, spot_price, open_share_price);
        if budget >= worst_case_deposit {
            budget - worst_case_deposit
        } else {
            fixed!(0)
        }
    }

    /// Gets the amount of base the trader will need to deposit for a short of
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
    pub fn get_short_deposit(
        &self,
        short_amount: FixedPoint,
        spot_price: FixedPoint,
        mut open_share_price: FixedPoint,
    ) -> FixedPoint {
        // If the open share price hasn't been set, we use the current share
        // price, since this is what will be set as the checkpoint share price
        // in the next transaction.
        if open_share_price == fixed!(0) {
            open_share_price = self.share_price();
        }

        // NOTE: The order of additions and subtractions is important to avoid underflows.
        short_amount.mul_div_down(self.share_price(), open_share_price)
            + self.flat_fee() * short_amount
            + self.curve_fee() * (fixed!(1e18) - spot_price) * short_amount
            - self.share_price() * self.short_principal(short_amount)
    }

    /// The derivative of the short deposit function with respect to the short
    /// amount. This allows us to use Newton's method to approximate the maximum
    /// short that a trader can open.
    ///
    /// Using this, calculating $D'(x)$ is straightforward:
    ///
    /// $$
    /// D'(x) = \tfrac{c}{c_0} - (c \cdot P'(x) - \phi_{curve} \cdot (1 - p)) + \phi_{flat}
    /// $$
    ///
    /// $$
    /// P'(x) = \tfrac{1}{c} \cdot (y + x)^{-t_s} \cdot \left(\tfrac{\mu}{c} \cdot (k - (y + x)^{1 - t_s}) \right)^{\tfrac{t_s}{1 - t_s}}
    /// $$
    fn short_deposit_derivative(
        &self,
        short_amount: FixedPoint,
        spot_price: FixedPoint,
        open_share_price: FixedPoint,
    ) -> FixedPoint {
        // NOTE: The order of additions and subtractions is important to avoid underflows.
        let payment_factor = (fixed!(1e18)
            / (self.bond_reserves() + short_amount).pow(self.time_stretch()))
            * self
                .theta(short_amount)
                .pow(self.time_stretch() / (fixed!(1e18) + self.time_stretch()));
        (self.share_price() / open_share_price)
            + self.flat_fee()
            + self.curve_fee() * (fixed!(1e18) - spot_price)
            - payment_factor
    }

    /// A helper function used in calculating the short deposit. Gets the amount
    /// of short principal that the LPs need to pay to back a short before fees
    /// are taken into consideration.
    ///
    /// Let the LP principal that backs $x$ shorts be given by $P(x)$. We can
    /// solve for this in terms of $x$ using the YieldSpace invariant:
    ///
    /// $$
    /// k = \tfrac{c}{\mu} \cdot (\mu \cdot (z - P(x)))^{1 - t_s} + (y + x)^{1 - t_s} \\
    /// \implies \\
    /// P(x) = z - \tfrac{1}{\mu} \cdot (\tfrac{\mu}{c} \cdot (k - (y + x)^{1 - t_s}))^{\tfrac{1}{1 - t_s}}
    /// $$
    fn short_principal(&self, short_amount: FixedPoint) -> FixedPoint {
        YieldSpaceState::from(self)
            .get_out_for_in(Asset::Bonds(short_amount), self.config.time_stretch.into())
    }

    /// A helper function used in calculating the short deposit.
    ///
    /// This calculates the inner component of the `short_principal` calculation,
    /// which makes the `short_principal` and `short_deposit_derivative` calculations
    /// easier. $\theta(x)$ is defined as:
    ///
    /// $$
    /// \theta(x) = \tfrac{\mu}{c} \cdot (k - (y + x)^{1 - t_s})
    /// $$
    fn theta(&self, short_amount: FixedPoint) -> FixedPoint {
        let k = YieldSpaceState::new(
            self.share_reserves(),
            self.bond_reserves(),
            self.share_price(),
            self.initial_share_price(),
        )
        .k(self.time_stretch());
        (self.initial_share_price() / self.share_price())
            * (k - (self.bond_reserves() + short_amount).pow(fixed!(1e18) - self.time_stretch()))
    }
}

#[cfg(test)]
mod tests {
    use std::panic;

    use ethers::types::U256;
    use eyre::Result;
    use hyperdrive_wrappers::wrappers::{
        i_hyperdrive::Checkpoint, mock_hyperdrive_math::MaxTradeParams,
    };
    use rand::{thread_rng, Rng};
    use test_utils::{
        agent::Agent,
        chain::{Chain, TestChain, TestChainWithMocks},
        constants::{FAST_FUZZ_RUNS, FUZZ_RUNS},
    };
    use tracing_test::traced_test;

    use super::*;

    /// This test differentially fuzzes the `get_max_long` function against the
    /// Solidity analogue `calculateMaxShort`. `calculateMaxShort` doesn't take
    /// a trader's budget into account, so it only provides a subset of
    /// `get_max_short`'s functionality. With this in mind, we provide
    /// `get_max_short` with a budget of `U256::MAX` to ensure that the two
    /// functions are equivalent.
    #[tokio::test]
    async fn fuzz_get_max_short_no_budget() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let actual =
                panic::catch_unwind(|| state.get_max_short(U256::MAX, fixed!(0), None, None));
            match chain
                .mock_hyperdrive_math()
                .calculate_max_short(MaxTradeParams {
                    share_reserves: state.info.share_reserves,
                    bond_reserves: state.info.bond_reserves,
                    longs_outstanding: state.info.longs_outstanding,
                    long_exposure: state.info.long_exposure,
                    time_stretch: state.config.time_stretch,
                    share_price: state.info.share_price,
                    initial_share_price: state.config.initial_share_price,
                    minimum_share_reserves: state.config.minimum_share_reserves,
                    curve_fee: state.config.fees.curve,
                    governance_fee: state.config.fees.governance,
                })
                .call()
                .await
            {
                Ok(expected) => {
                    assert_eq!(actual.unwrap(), FixedPoint::from(expected));
                }
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }

    #[traced_test]
    #[tokio::test]
    async fn test_get_max_short() -> Result<()> {
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
        let config = alice.get_config().clone();

        for _ in 0..*FUZZ_RUNS {
            // Snapshot the chain.
            let id = chain.snapshot().await?;

            // TODO: We should fuzz over a range of fixed rates.
            //
            // Fund Alice and Bob.
            let fixed_rate = fixed!(0.05e18);
            let contribution = rng.gen_range(fixed!(100_000e18)..=fixed!(100_000_000e18));
            let budget = rng.gen_range(fixed!(10e18)..=fixed!(100_000_000e18));
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

            // Get the current state of the pool.
            let state = alice.get_state().await?;
            let Checkpoint {
                share_price: open_share_price,
                ..
            } = alice
                .get_checkpoint(state.to_checkpoint(alice.now().await?))
                .await?;
            let global_max_short = state.get_max_short(U256::MAX, open_share_price, None, None);

            // Bob opens a max short position. We allow for a very small amount
            // of slippage to account for interest accrual between the time the
            // calculation is performed and the transaction is submitted.
            let slippage_tolerance = fixed!(0.0001e18);
            let max_short = bob.get_max_short(Some(slippage_tolerance)).await?;
            bob.open_short(max_short, None).await?;

            // The max short should either be equal to the global max short in
            // the case that the trader isn't budget constrained or the budget
            // should be consumed except for a small epsilon.
            if max_short != global_max_short {
                // We currently allow up to a tolerance of 0.1%, which means
                // that the max short is always consuming at least 99.9% of
                // the budget.
                let error_tolerance = fixed!(0.001e18);
                assert!(
                    bob.base() < budget * (fixed!(1e18) - slippage_tolerance) * error_tolerance,
                    "expected (base={}) < (budget={}) * {} = {}",
                    bob.base(),
                    budget,
                    error_tolerance,
                    budget * error_tolerance
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
