use std::cmp::min;

use ethers::types::{Address, I256, U256};
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, int256, uint256};
use hyperdrive_wrappers::wrappers::i_hyperdrive::{Fees, PoolConfig, PoolInfo};
use rand::{
    distributions::{Distribution, Standard},
    Rng,
};

use crate::yield_space::{Asset, State as YieldSpaceState};

#[derive(Debug)]
pub struct State {
    pub config: PoolConfig,
    pub info: PoolInfo,
}

impl From<&State> for YieldSpaceState {
    fn from(s: &State) -> Self {
        Self::new(
            s.info.share_reserves.into(),
            s.info.bond_reserves.into(),
            s.info.share_price.into(),
            s.config.initial_share_price.into(),
        )
    }
}

impl Distribution<State> for Standard {
    // TODO: It may be better for this to be a uniform sampler and have a test
    // sampler that is more restrictive like this.
    fn sample<R: Rng + ?Sized>(&self, rng: &mut R) -> State {
        let config = PoolConfig {
            base_token: Address::zero(),
            governance: Address::zero(),
            fee_collector: Address::zero(),
            fees: Fees {
                curve: uint256!(0),
                flat: uint256!(0),
                governance: uint256!(0),
            },
            initial_share_price: rng.gen_range(fixed!(0.5e18)..=fixed!(2.5e18)).into(),
            minimum_share_reserves: rng.gen_range(fixed!(0.1e18)..=fixed!(1e18)).into(),
            time_stretch: rng.gen_range(fixed!(0.005e18)..=fixed!(0.5e18)).into(),
            position_duration: rng
                .gen_range(
                    FixedPoint::from(60 * 60 * 24 * 91)..=FixedPoint::from(60 * 60 * 24 * 365),
                )
                .into(),
            checkpoint_duration: rng
                .gen_range(FixedPoint::from(60 * 60)..=FixedPoint::from(60 * 60 * 24))
                .into(),
            oracle_size: fixed!(0).into(),
            update_gap: fixed!(0).into(),
        };
        // We need the spot price to be less than or equal to 1, so we need to
        // generate the bond reserves so that mu * z <= y
        let share_reserves = rng.gen_range(fixed!(1_000e18)..=fixed!(100_000_000e18));
        let info = PoolInfo {
            share_reserves: share_reserves.into(),
            bond_reserves: rng
                .gen_range(
                    share_reserves * FixedPoint::from(config.initial_share_price)
                        ..=fixed!(1_000_000_000e18),
                )
                .into(),
            long_exposure: fixed!(0).into(),
            share_price: rng.gen_range(fixed!(0.5e18)..=fixed!(2.5e18)).into(),
            longs_outstanding: rng.gen_range(fixed!(0)..=fixed!(100_000e18)).into(),
            shorts_outstanding: rng.gen_range(fixed!(0)..=fixed!(100_000e18)).into(),
            long_average_maturity_time: rng
                .gen_range(fixed!(0)..=FixedPoint::from(60 * 60 * 24 * 365))
                .into(),
            short_average_maturity_time: rng
                .gen_range(fixed!(0)..=FixedPoint::from(60 * 60 * 24 * 365))
                .into(),
            short_base_volume: rng.gen_range(fixed!(0)..=fixed!(100_000e18)).into(),
            lp_total_supply: rng
                .gen_range(fixed!(1_000e18)..=fixed!(100_000_000e18))
                .into(),
            // TODO: This should be calculated based on the other values.
            lp_share_price: rng.gen_range(fixed!(0.01e18)..=fixed!(5e18)).into(),
            withdrawal_shares_proceeds: rng.gen_range(fixed!(0)..=fixed!(100_000e18)).into(),
            withdrawal_shares_ready_to_withdraw: rng
                .gen_range(fixed!(1_000e18)..=fixed!(100_000_000e18))
                .into(),
        };
        State { config, info }
    }
}

impl State {
    /// Creates a new `State` from the given `PoolConfig` and `PoolInfo`.
    pub fn new(config: PoolConfig, info: PoolInfo) -> Self {
        Self { config, info }
    }

    /// Gets the pool's spot price.
    pub fn get_spot_price(&self) -> FixedPoint {
        YieldSpaceState::from(self).get_spot_price(self.config.time_stretch.into())
    }

    /// Gets the pool's spot rate.
    pub fn get_spot_rate(&self) -> FixedPoint {
        let annualized_time = FixedPoint::from(self.config.position_duration)
            / FixedPoint::from(U256::from(60 * 60 * 24 * 365));
        let spot_price = self.get_spot_price();
        (fixed!(1e18) - spot_price) / (spot_price * annualized_time)
    }

    /// Converts a timestamp to the checkpoint timestamp that it corresponds to.
    pub fn to_checkpoint(&self, time: U256) -> U256 {
        time - time % self.config.checkpoint_duration
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
        let (max_long_base, ..) = self.max_long(maybe_max_iterations.unwrap_or(7));

        // If the maximum long that can be opened is less than the budget, then
        // we return the maximum long that can be opened. Otherwise, we return
        // the budget.
        min(max_long_base, budget)
    }

    fn max_long(&self, max_iterations: usize) -> (FixedPoint, FixedPoint) {
        let mut base_amount = fixed!(0);
        let mut bond_amount = fixed!(0);

        // We first solve for the maximum buy that is possible on the YieldSpace
        // curve. This will give us an upper bound on our maximum buy by giving
        // us the maximum buy that is possible without going into negative
        // interest territory. Hyperdrive has solvency requirements since it
        // mints longs on demand. If the maximum buy satisfies our solvency
        // checks, then we're done. If not, then we need to solve for the
        // maximum trade size iteratively.
        let (mut dz, mut dy) =
            YieldSpaceState::from(self).get_max_buy(self.config.time_stretch.into());
        if self.share_reserves() + dz
            >= (self.longs_outstanding() + dy) / self.share_price() + self.minimum_share_reserves()
        {
            base_amount = dz * self.share_price();
            bond_amount = dy;
            return (base_amount, bond_amount);
        }

        // To make an initial guess for the iterative approximation, we consider
        // the solvency check to be the error that we want to reduce. The amount
        // the long buffer exceeds the share reserves is given by
        // (y_l + dy) / c - (z + dz). Since the error could be large, we'll use
        // the realized price of the trade instead of the spot price to
        // approximate the change in trade output. This gives us dy = c * 1/p * dz.
        // Substituting this into error equation and setting the error equal to
        // zero allows us to solve for the initial guess as:
        //
        // (y_l + c * 1/p * dz) / c + z_min - (z + dz) = 0
        //              =>
        // (1/p - 1) * dz = z - y_l/c - z_min
        //              =>
        // dz = (z - y_l/c - z_min) * (p / (p - 1))
        let mut p = self.share_price().mul_div_down(dz, dy);
        dz = (self.share_reserves()
            - self.longs_outstanding() / self.share_price()
            - self.minimum_share_reserves())
        .mul_div_down(p, fixed!(1e18) - p);
        dy = YieldSpaceState::from(self)
            .get_out_for_in(Asset::Shares(dz), self.config.time_stretch.into());

        // Our maximum long will be the largest trade size that doesn't fail
        // the solvency check.
        for _ in 0..max_iterations {
            // If the approximation error is greater than zero and the solution
            // is the largest we've found so far, then we update our result.
            let approximation_error = I256::from(self.share_reserves() + dz)
                - I256::from((self.longs_outstanding() + dy) / self.share_price())
                - I256::from(self.minimum_share_reserves());
            if approximation_error > int256!(0) && dz * self.share_price() > base_amount {
                base_amount = dz * self.share_price();
                bond_amount = dy;
            }

            // Even though YieldSpace isn't linear, we can use a linear
            // approximation to get closer to the optimal solution. Our guess
            // should bring us close enough to the optimal point that we can
            // linearly approximate the change in error using the current spot
            // price.
            //
            // We can approximate the change in the trade output with respect to
            // trade size as dy' = c * (1/p) * dz'. Substituting this into our
            // error equation and setting the error equation equal to zero
            // allows us to solve for the trade size update:
            //
            // (y_l + dy + c * (1/p) * dz') / c + z_min - (z + dz + dz') = 0
            //                  =>
            // (1/p - 1) * dz' = (z + dz) - (y_l + dy) / c - z_min
            //                  =>
            // dz' = ((z + dz) - (y_l + dy) / c - z_min) * (p / (p - 1)).
            p = YieldSpaceState::new(
                self.share_reserves() + dz,
                self.bond_reserves() - dy,
                self.share_price(),
                self.config.initial_share_price.into(),
            )
            .get_spot_price(self.config.time_stretch.into());
            if p >= fixed!(1e18) {
                // If the spot price is greater than one and the error is
                // positive,
                break;
            }
            if approximation_error < int256!(0) {
                let delta = FixedPoint::from((-approximation_error).into_raw())
                    .mul_div_down(p, fixed!(1e18) - p);
                if dz > delta {
                    dz -= delta;
                } else {
                    dz = fixed!(0);
                }
            } else {
                dz += FixedPoint::from(approximation_error.into_raw())
                    .mul_div_down(p, fixed!(1e18) - p);
            }
            dy = YieldSpaceState::from(self)
                .get_out_for_in(Asset::Shares(dz), self.config.time_stretch.into());
        }

        (base_amount, bond_amount)
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
    pub fn get_max_short(
        &self,
        budget: FixedPoint,
        open_share_price: FixedPoint,
        maybe_conservative_price: Option<FixedPoint>,
        maybe_max_iterations: Option<usize>,
    ) -> FixedPoint {
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
        let (max_short_base, mut max_short_bonds) = self.max_short(spot_price, open_share_price);
        if max_short_base <= budget {
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
            println!(
                "diff={}",
                budget - self.short_deposit(max_short_bonds, spot_price, open_share_price)
            );
            max_short_bonds = max_short_bonds
                + (budget - self.short_deposit(max_short_bonds, spot_price, open_share_price))
                    / self.short_deposit_derivative(max_short_bonds, spot_price, open_share_price);
        }
        println!(
            "diff={}",
            budget - self.short_deposit(max_short_bonds, spot_price, open_share_price)
        );

        // Verify that the max short satisfies the budget.
        if budget < self.short_deposit(max_short_bonds, spot_price, open_share_price) {
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
        let base_amount = self.short_deposit(short_amount, spot_price, open_share_price);

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
            if budget >= self.short_deposit(guess, spot_price, open_share_price) {
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
        let worst_case_deposit = self.short_deposit(budget, spot_price, open_share_price);
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
    fn short_deposit(
        &self,
        short_amount: FixedPoint,
        spot_price: FixedPoint,
        open_share_price: FixedPoint,
    ) -> FixedPoint {
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

    /// Getters ///

    fn share_reserves(&self) -> FixedPoint {
        self.info.share_reserves.into()
    }

    fn minimum_share_reserves(&self) -> FixedPoint {
        self.config.minimum_share_reserves.into()
    }

    fn bond_reserves(&self) -> FixedPoint {
        self.info.bond_reserves.into()
    }

    fn longs_outstanding(&self) -> FixedPoint {
        self.info.longs_outstanding.into()
    }

    fn share_price(&self) -> FixedPoint {
        self.info.share_price.into()
    }

    fn initial_share_price(&self) -> FixedPoint {
        self.config.initial_share_price.into()
    }

    fn time_stretch(&self) -> FixedPoint {
        self.config.time_stretch.into()
    }

    fn flat_fee(&self) -> FixedPoint {
        self.config.fees.flat.into()
    }

    fn curve_fee(&self) -> FixedPoint {
        self.config.fees.curve.into()
    }
}

#[cfg(test)]
mod tests {
    use std::{convert::TryFrom, panic, sync::Arc, time::Duration};

    use ethers::{
        core::utils::Anvil,
        middleware::SignerMiddleware,
        providers::{Http, Provider},
        signers::{LocalWallet, Signer},
        types::U256,
        utils::AnvilInstance,
    };
    use eyre::Result;
    use hyperdrive_wrappers::wrappers::mock_hyperdrive_math::{MaxTradeParams, MockHyperdriveMath};
    use rand::{thread_rng, Rng};
    use test_utils::{agent::Agent, test_chain::TestChain};

    use super::*;

    const FUZZ_RUNS: usize = 10_000;

    struct TestRunner {
        mock: MockHyperdriveMath<SignerMiddleware<Provider<Http>, LocalWallet>>,
        _anvil: AnvilInstance, // NOTE: Avoid dropping this until the end of the test.
    }

    // FIXME: DRY this up into a test-utils crate.
    //
    /// Set up a test blockchain with MockHyperdriveMath deployed.
    async fn setup() -> Result<TestRunner> {
        let anvil = Anvil::new().spawn();
        let wallet: LocalWallet = anvil.keys()[0].clone().into();
        let provider =
            Provider::<Http>::try_from(anvil.endpoint())?.interval(Duration::from_millis(10u64));
        let client = Arc::new(SignerMiddleware::new(
            provider,
            wallet.with_chain_id(anvil.chain_id()),
        ));
        let mock = MockHyperdriveMath::deploy(client, ())?.send().await?;
        Ok(TestRunner {
            mock,
            _anvil: anvil,
        })
    }

    #[tokio::test]
    async fn fuzz_get_max_long() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let state = rng.gen::<State>();
            let max_iterations = rng.gen_range(0..=25);
            let actual =
                panic::catch_unwind(|| state.get_max_long(U256::MAX.into(), Some(max_iterations)));
            match runner
                .mock
                .calculate_max_long(
                    MaxTradeParams {
                        share_reserves: state.info.share_reserves,
                        bond_reserves: state.info.bond_reserves,
                        longs_outstanding: state.info.longs_outstanding,
                        time_stretch: state.config.time_stretch,
                        share_price: state.info.share_price,
                        initial_share_price: state.config.initial_share_price,
                        minimum_share_reserves: state.config.minimum_share_reserves,
                    },
                    max_iterations.into(),
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

    /// This test differentially fuzzes the `get_max_long` function against the
    /// Solidity analogue `calculateMaxShort`. `calculateMaxShort` doesn't take
    /// a trader's budget into account, so it only provides a subset of
    /// `get_max_short`'s functionality. With this in mind, we provide
    /// `get_max_short` with a budget of `U256::MAX` to ensure that the two
    /// functions are equivalent.
    #[tokio::test]
    async fn fuzz_get_max_short_no_budget() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let state = rng.gen::<State>();
            let actual = panic::catch_unwind(|| {
                state.get_max_short(U256::MAX.into(), fixed!(0), None, None)
            });
            match runner
                .mock
                .calculate_max_short(MaxTradeParams {
                    share_reserves: state.info.share_reserves,
                    bond_reserves: state.info.bond_reserves,
                    longs_outstanding: state.info.longs_outstanding,
                    time_stretch: state.config.time_stretch,
                    share_price: state.info.share_price,
                    initial_share_price: state.config.initial_share_price,
                    minimum_share_reserves: state.config.minimum_share_reserves,
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

    #[tokio::test]
    async fn test_get_max_short() -> Result<()> {
        // Spawn a test chain and create two agents -- Alice and Bob. Alice
        // is funded with a large amount of capital so that she can initialize
        // the pool. Bob is funded with a small amount of capital so that we
        // can test `get_max_short` when budget is the primary constraint.
        let chain = TestChain::new(Some("http://localhost:8545"), 2).await?;
        let mut alice = Agent::new(
            chain.accounts[0].clone(),
            chain.provider.clone(),
            chain.addresses.clone(),
            None,
        )
        .await?;
        let mut bob = Agent::new(
            chain.accounts[1].clone(),
            chain.provider,
            chain.addresses,
            None,
        )
        .await?;

        // Alice initializes the pool.
        let (fixed_rate, contribution) = (fixed!(0.05e18), fixed!(100_000_000e18));
        alice.fund(contribution).await?;
        alice.initialize(fixed_rate, contribution).await?;

        // Bob opens a max short position.
        let mut rng = thread_rng();
        let budget = rng.gen_range(fixed!(10e18)..=fixed!(100_000_000e18));
        bob.fund(budget).await?;
        let max_short = bob.get_max_short().await?;
        println!("max_short: {}", max_short);
        bob.open_short(max_short).await?;

        // Verify that essentially all of Bob's budget is consumed.
        assert!(bob.base() < fixed!(1e18));

        Ok(())
    }
}
