use crate::yield_space::{Asset, State as YieldSpaceState};
use ethers::types::{Address, I256, U256};
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, int256, uint256};
use hyperdrive_wrappers::wrappers::i_hyperdrive::{Fees, PoolConfig, PoolInfo};
use rand::distributions::{Distribution, Standard};
use rand::Rng;
use std::cmp::min;

#[derive(Debug)]
pub struct State {
    config: PoolConfig,
    info: PoolInfo,
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
    pub fn get_max_short(
        &self,
        budget: FixedPoint,
        open_share_price: FixedPoint,
        maybe_max_iterations: Option<usize>,
    ) -> FixedPoint {
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
        // for the short deposit to consume the entire budget.
        for _ in 0..maybe_max_iterations.unwrap_or(3) {
            max_short_bonds = max_short_bonds
                - self.short_deposit(max_short_bonds, spot_price, open_share_price)
                    / self.short_deposit_derivative(max_short_bonds, spot_price, open_share_price);
        }

        // Verify that the max short satisfies the budget.
        if budget < self.short_deposit(max_short_bonds, spot_price, open_share_price) {
            panic!("max short exceeded budget");
        }

        max_short_bonds
    }

    /// Converts a timestamp to the checkpoint timestamp that it corresponds to.
    pub fn to_checkpoint(&self, time: U256) -> U256 {
        time - time % self.config.checkpoint_duration
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

    /// Gets the amount of base the trader will need to deposit for a short of
    /// a given size.
    fn short_deposit(
        &self,
        short_amount: FixedPoint,
        spot_price: FixedPoint,
        open_share_price: FixedPoint,
    ) -> FixedPoint {
        short_amount
            + (self.share_price() - open_share_price) * short_amount
            + FixedPoint::from(self.config.fees.flat) * short_amount
            + (fixed!(1e18) - spot_price) * FixedPoint::from(self.config.fees.curve) * short_amount
            - self.share_price() * self.short_principal(short_amount)
    }

    /// The derivative of the short deposit function with respect to the short
    /// amount. This allows us to use Newton's method to approximate the maximum
    /// short that a trader can open.
    fn short_deposit_derivative(
        &self,
        short_amount: FixedPoint,
        spot_price: FixedPoint,
        open_share_price: FixedPoint,
    ) -> FixedPoint {
        let payment_factor = (fixed!(1e18)
            / (self.bond_reserves() + short_amount).pow(self.time_stretch()))
            * self
                .theta(short_amount)
                .pow(self.time_stretch() / (fixed!(1e18) + self.time_stretch()));
        fixed!(1e18)
            + (self.share_price() - open_share_price)
            + FixedPoint::from(self.config.fees.flat)
            + (fixed!(1e18) - spot_price) * FixedPoint::from(self.config.fees.curve)
            - payment_factor
    }

    /// A helper function used in calculating the short deposit. This corresponds
    /// to the amount of base that the LP will pay for the shorted bonds before
    /// fees.
    fn short_principal(&self, x: FixedPoint) -> FixedPoint {
        self.share_reserves()
            - (fixed!(1e18) / self.initial_share_price())
                * self
                    .theta(x)
                    .pow(fixed!(1e18) / (fixed!(1e18) - self.time_stretch()))
    }

    /// A helper function used in calculating the short deposit. This calculates
    /// a component of the `short_principal` calculation.
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

    fn bond_reserves(&self) -> FixedPoint {
        self.info.bond_reserves.into()
    }

    fn share_price(&self) -> FixedPoint {
        self.info.share_price.into()
    }

    fn initial_share_price(&self) -> FixedPoint {
        self.config.initial_share_price.into()
    }

    fn minimum_share_reserves(&self) -> FixedPoint {
        self.config.minimum_share_reserves.into()
    }

    fn longs_outstanding(&self) -> FixedPoint {
        self.info.longs_outstanding.into()
    }

    fn time_stretch(&self) -> FixedPoint {
        self.config.time_stretch.into()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
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
    use std::{convert::TryFrom, panic, sync::Arc, time::Duration};

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

    #[tokio::test]
    async fn fuzz_get_max_short() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let state = rng.gen::<State>();
            let actual =
                panic::catch_unwind(|| state.get_max_short(U256::MAX.into(), fixed!(0), None));
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
}
