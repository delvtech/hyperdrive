use ethers::types::I256;
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, int256};

use super::State;
use crate::{get_effective_share_reserves, Asset, YieldSpace};

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
        let y_max = (self.k()
            - (self.share_price() / self.initial_share_price())
                * (self.initial_share_price() * self.minimum_share_reserves())
                    .pow(fixed!(1e18) - self.time_stretch()))
        .pow(fixed!(1e18).div_up(fixed!(1e18) - self.time_stretch()));
        ((self.initial_share_price() * self.minimum_share_reserves()) / y_max)
            .pow(self.time_stretch())
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

    // TODO: Make it clear to the consumer that the maximum number of iterations
    // is 2 * max_iterations.
    //
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
    pub fn get_max_short<F1: Into<FixedPoint>, F2: Into<FixedPoint>, I: Into<I256>>(
        &self,
        budget: F1,
        open_share_price: F2,
        checkpoint_exposure: I,
        maybe_conservative_price: Option<FixedPoint>, // TODO: Is there a nice way of abstracting the inner type?
        maybe_max_iterations: Option<usize>,
    ) -> FixedPoint {
        let budget = budget.into();
        let open_share_price = open_share_price.into();
        let checkpoint_exposure = checkpoint_exposure.into();

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
        let mut max_bond_amount = self.absolute_max_short(
            spot_price,
            open_share_price,
            checkpoint_exposure,
            maybe_max_iterations,
        );
        if self.get_short_deposit(max_bond_amount, spot_price, open_share_price) <= budget {
            return max_bond_amount;
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
        max_bond_amount = self.max_short_guess(
            budget,
            spot_price,
            open_share_price,
            maybe_conservative_price,
        );
        for _ in 0..maybe_max_iterations.unwrap_or(7) {
            max_bond_amount += (budget
                - self.get_short_deposit(max_bond_amount, spot_price, open_share_price))
                / self.short_deposit_derivative(max_bond_amount, spot_price, open_share_price);
        }

        // Verify that the max short satisfies the budget.
        if budget < self.get_short_deposit(max_bond_amount, spot_price, open_share_price) {
            panic!("max short exceeded budget");
        }

        max_bond_amount
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

    /// Gets the absolute max short that can be opened without violating the
    /// pool's solvency constraints.
    fn absolute_max_short(
        &self,
        spot_price: FixedPoint,
        open_share_price: FixedPoint,
        checkpoint_exposure: I256,
        maybe_max_iterations: Option<usize>,
    ) -> FixedPoint {
        // TODO: We need to enforce these properties in the Solidity
        // implementation and test them.
        //
        // We start by calculating the maximum short that can be opened on the
        // YieldSpace curve. Both $z \geq z_{min}$ and $z - \zeta \geq z_{min}$
        // must hold, which allows us to solve directly for the optimal bond
        // reserves.
        let absolute_max_bond_amount = {
            let optimal_share_reserves = if self.share_adjustment() >= int256!(0) {
                // If the share adjustment is greater than zero, then
                // $z > z - \zeta$, so $z - \zeta \geq z_{min}$ is the
                // constraint that matters. Our optimal share reserves are given
                // by $z = \zeta + z_{min}$.
                FixedPoint::from(self.share_adjustment()) + self.minimum_share_reserves()
            } else {
                // If the share adjustment is less than zero, then
                // $z - \zeta > z$ as $z \geq z_{min}$ is the salient constraint.
                // Our optimal share reserves are given by $z = z_{min}$.
                self.minimum_share_reserves()
            };
            let optimal_effective_share_reserves =
                get_effective_share_reserves(optimal_share_reserves, self.share_adjustment());
            let optimal_bond_reserves = (self.k()
                - (self.share_price() / self.initial_share_price())
                    * (self.initial_share_price() * optimal_effective_share_reserves)
                        .pow(fixed!(1e18) - self.time_stretch()))
            .pow(fixed!(1e18).div_up(fixed!(1e18) - self.time_stretch()));
            optimal_bond_reserves - self.bond_reserves()
        };
        if self
            .solvency_after_short(
                absolute_max_bond_amount,
                spot_price,
                open_share_price,
                checkpoint_exposure,
            )
            .is_some()
        {
            return absolute_max_bond_amount;
        }

        // Use Newton's method to iteratively approach a solution. We use pool's
        // solvency $S(x)$ w.r.t. the amount of bonds shorted $x$ as our
        // objective function, which will converge to the maximum short amount
        // when $S(x) = 0$. The derivative of $S(x)$ is negative (since solvency
        // decreases as more shorts are opened). The fixed point library doesn't
        // support negative numbers, so we use the negation of the derivative to
        // side-step the issue.
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
        let mut max_bond_amount = self.absolute_max_short_guess(spot_price, checkpoint_exposure);
        let mut maybe_solvency = self.solvency_after_short(
            max_bond_amount,
            spot_price,
            open_share_price,
            checkpoint_exposure,
        );
        if maybe_solvency.is_none() {
            panic!("Initial guess in `max_short` is insolvent.");
        }
        let mut solvency = maybe_solvency.unwrap();
        for _ in 0..maybe_max_iterations.unwrap_or(7) {
            // If the max bond amount is equal to or exceeds the absolute max,
            // we've gone too far and something has gone wrong.
            if max_bond_amount >= absolute_max_bond_amount {
                panic!("Reached absolute max bond amount in `max_short`.");
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
            let maybe_derivative =
                self.solvency_after_short_derivative(max_bond_amount, spot_price);
            if maybe_derivative.is_none() {
                break;
            }
            let possible_max_bond_amount = max_bond_amount + solvency / maybe_derivative.unwrap();
            maybe_solvency = self.solvency_after_short(
                possible_max_bond_amount,
                spot_price,
                open_share_price,
                checkpoint_exposure,
            );
            if let Some(s) = maybe_solvency {
                solvency = s;
                max_bond_amount = possible_max_bond_amount;
            } else {
                break;
            }
        }

        max_bond_amount
    }

    /// Gets an initial guess for the absolute max short. This is a conservative
    /// guess that will be less than the true absolute max short, which is what
    /// we need to start Newton's method.
    ///
    /// To calculate our guess, we assume an unrealistically good realized
    /// price $p_r$ for opening the short. This allows us to approximate
    /// $P(x) \approx \tfrac{1}{c} \cdot p_r \cdot x$. Plugging this
    /// into our solvency function $s(x)$, we get an approximation of our
    /// solvency as:
    ///
    /// $$
    /// S(x) \approx (z_0 - \tfrac{1}{c} \cdot (
    ///                  p_r - \phi_{c} \cdot (1 - p) + \phi_{g} \cdot \phi_{c} \cdot (1 - p)
    ///              )) - \tfrac{e_0 - max(e_{c}, 0)}{c} - z_{min}
    /// $$
    ///
    /// Setting this equal to zero, we can solve for our initial guess:
    ///
    /// $$
    /// x = \frac{c \cdot (s_0 + \tfrac{max(e_{c}, 0)}{c})}{
    ///         p_r - \phi_{c} \cdot (1 - p) + \phi_{g} \cdot \phi_{c} \cdot (1 - p)
    ///     }
    /// $$
    fn absolute_max_short_guess(
        &self,
        spot_price: FixedPoint,
        checkpoint_exposure: I256,
    ) -> FixedPoint {
        let estimate_price = spot_price;
        let checkpoint_exposure =
            FixedPoint::from(checkpoint_exposure.max(I256::zero())) / self.share_price();
        (self.share_price() * (self.get_solvency() + checkpoint_exposure))
            / (estimate_price - self.curve_fee() * (fixed!(1e18) - spot_price)
                + self.governance_fee() * self.curve_fee() * (fixed!(1e18) - spot_price))
    }

    /// Gets the derivative of the short deposit function with respect to the
    /// short amount. This allows us to use Newton's method to approximate the
    /// maximum short that a trader can open.
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

    /// Gets the pool's solvency after opening a short.
    ///
    /// We can express the pool's solvency after opening a short of $x$ bonds as:
    ///
    /// $$
    /// s(x) = z(x) - \tfrac{e(x)}{c} - z_{min}
    /// $$
    ///
    /// where $z(x)$ represents the pool's share reserves after opening the short:
    ///
    /// $$
    /// z(x) = z_0 - \left(
    ///            P(x) - \left( \tfrac{c(x)}{c} - \tfrac{g(x)}{c} \right)
    ///        \right)
    /// $$
    ///
    /// and $e(x)$ represents the pool's exposure after opening the short:
    ///
    /// $$
    /// e(x) = e_0 - min(x + D(x), max(e_{c}, 0))
    /// $$
    ///
    /// We simplify our $e(x)$ formula by noting that the max short is only
    /// constrained by solvency when $x + D(x) > max(e_{c}, 0)$ since $x + D(x)$
    /// grows faster than $P(x) - \tfrac{\phi_{c}}{c} \cdot \left( 1 - p \right) \cdot x$.
    /// With this in mind, $min(x + D(x), max(e_{c}, 0)) = max(e_{c}, 0)$
    /// whenever solvency is actually a constraint, so we can write:
    ///
    /// $$
    /// e(x) = e_0 - max(e_{c}, 0)
    /// $$
    fn solvency_after_short(
        &self,
        short_amount: FixedPoint,
        spot_price: FixedPoint,
        open_share_price: FixedPoint,
        checkpoint_exposure: I256,
    ) -> Option<FixedPoint> {
        let share_reserves = self.share_reserves()
            - (self.short_principal(short_amount)
                - (self.short_curve_fee(short_amount, spot_price)
                    - self.short_governance_fee(short_amount, spot_price))
                    / self.share_price());
        let exposure = {
            let checkpoint_exposure: FixedPoint = checkpoint_exposure.max(I256::zero()).into();
            (self.long_exposure() - checkpoint_exposure) / self.share_price()
        };
        if share_reserves >= exposure + self.minimum_share_reserves() {
            Some(share_reserves - exposure - self.minimum_share_reserves())
        } else {
            None
        }
    }

    /// Gets the derivative of the pool's solvency w.r.t. the short amount.
    ///
    /// The derivative is calculated as:
    ///
    /// \begin{aligned}
    /// s'(x) &= z'(x)
    ///       &= -(P'(x) - \tfrac{\phi_{c}}{c} \cdot (1 - p))
    ///       &= -P'(x) + \tfrac{\phi_{c}}{c} \cdot (1 - p)
    /// \end{aligned}
    ///
    /// Since solvency decreases as the short amount increases, we negate the
    /// derivative. This avoids issues with the fixed point library which
    /// doesn't support negative values.
    fn solvency_after_short_derivative(
        &self,
        short_amount: FixedPoint,
        spot_price: FixedPoint,
    ) -> Option<FixedPoint> {
        let lhs = self.short_principal_derivative(short_amount);
        let rhs = self.curve_fee() * (fixed!(1e18) - spot_price) / self.share_price();
        if lhs >= rhs {
            Some(lhs - rhs)
        } else {
            None
        }
    }

    /// Gets the amount of short principal that the LPs need to pay to back a
    /// short before fees are taken into consideration, $P(x)$.
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
        self.get_out_for_in(Asset::Bonds(short_amount))
    }

    /// Gets the derivative of the short principal $P(x)$ w.r.t. the amount of
    /// bonds that are shorted $x$.
    ///
    /// The derivative is calculated as:
    ///
    /// $$
    /// P'(x) = \tfrac{1}{c} \cdot (y + x)^{-t_s} \cdot \left(
    ///             \tfrac{\mu}{c} \cdot (k - (y + x)^{1 - t_s})
    ///         \right)^{\tfrac{t_s}{1 - t_s}}
    /// $$
    fn short_principal_derivative(&self, short_amount: FixedPoint) -> FixedPoint {
        let lhs = fixed!(1e18)
            / (self
                .share_price()
                .mul_up((self.bond_reserves() + short_amount).pow(self.time_stretch())));
        let rhs = ((self.initial_share_price() / self.share_price())
            * (self.k()
                - (self.bond_reserves() + short_amount).pow(fixed!(1e18) - self.time_stretch())))
        .pow(
            self.time_stretch()
                .div_up(fixed!(1e18) - self.time_stretch()),
        );
        lhs * rhs
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
        (self.initial_share_price() / self.share_price())
            * (self.k()
                - (self.bond_reserves() + short_amount).pow(fixed!(1e18) - self.time_stretch()))
    }

    /// Gets the curve fee paid by the trader when they open a short.
    fn short_curve_fee(&self, short_amount: FixedPoint, spot_price: FixedPoint) -> FixedPoint {
        self.curve_fee() * (fixed!(1e18) - spot_price) * short_amount
    }

    /// Gets the governance fee paid by the trader when they open a short.
    fn short_governance_fee(&self, short_amount: FixedPoint, spot_price: FixedPoint) -> FixedPoint {
        self.governance_fee() * self.short_curve_fee(short_amount, spot_price)
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

    /// This test differentially fuzzes the `get_max_short` function against the
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
            let checkpoint_exposure = {
                let value = rng.gen_range(fixed!(0)..=fixed!(10_000_000e18));
                if rng.gen() {
                    -I256::from(value)
                } else {
                    I256::from(value)
                }
            };
            let max_iterations = 7;
            let actual = panic::catch_unwind(|| {
                state.get_max_short(
                    U256::MAX,
                    fixed!(0),
                    checkpoint_exposure,
                    None,
                    Some(max_iterations),
                )
            });
            match chain
                .mock_hyperdrive_math()
                .calculate_max_short(
                    MaxTradeParams {
                        share_reserves: state.info.share_reserves,
                        bond_reserves: state.info.bond_reserves,
                        longs_outstanding: state.info.longs_outstanding,
                        long_exposure: state.info.long_exposure,
                        share_adjustment: state.info.share_adjustment,
                        time_stretch: state.config.time_stretch,
                        share_price: state.info.share_price,
                        initial_share_price: state.config.initial_share_price,
                        minimum_share_reserves: state.config.minimum_share_reserves,
                        curve_fee: state.config.fees.curve,
                        governance_fee: state.config.fees.governance,
                    },
                    checkpoint_exposure,
                    max_iterations.into(),
                )
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
                long_exposure: checkpoint_exposure,
                ..
            } = alice
                .get_checkpoint(state.to_checkpoint(alice.now().await?))
                .await?;
            let global_max_short =
                state.get_max_short(U256::MAX, open_share_price, checkpoint_exposure, None, None);

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
