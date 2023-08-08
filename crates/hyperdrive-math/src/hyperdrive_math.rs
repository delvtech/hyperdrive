use crate::yield_space::{Asset, State as YieldSpaceState};
use ethers::types::{Address, I256, U256};
use ethers::utils::parse_units;
use fixed_point::FixedPoint;
use hyperdrive_wrappers::wrappers::i_hyperdrive::{Fees, PoolConfig, PoolInfo};
use rand::distributions::{Distribution, Standard};
use rand::Rng;

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
        State {
            config: PoolConfig {
                base_token: Address::zero(),
                governance: Address::zero(),
                fee_collector: Address::zero(),
                fees: Fees {
                    curve: FixedPoint::zero().into(),
                    flat: FixedPoint::zero().into(),
                    governance: FixedPoint::zero().into(),
                },
                initial_share_price: rng
                    .gen_range(
                        FixedPoint::from(parse_units("0.5", 18).unwrap())
                            ..=FixedPoint::from(parse_units("2.5", 18).unwrap()),
                    )
                    .into(),
                minimum_share_reserves: rng
                    .gen_range(
                        FixedPoint::from(parse_units("0.1", 18).unwrap())
                            ..=FixedPoint::from(parse_units("10", 18).unwrap()),
                    )
                    .into(),
                time_stretch: rng
                    .gen_range(
                        FixedPoint::from(parse_units("0.005", 18).unwrap())
                            ..=FixedPoint::from(parse_units("0.5", 18).unwrap()),
                    )
                    .into(),
                position_duration: rng
                    .gen_range(
                        FixedPoint::from(60 * 60 * 24 * 91)..=FixedPoint::from(60 * 60 * 24 * 365),
                    )
                    .into(),
                checkpoint_duration: rng
                    .gen_range(FixedPoint::from(60 * 60)..=FixedPoint::from(60 * 60 * 24))
                    .into(),
                oracle_size: FixedPoint::zero().into(),
                update_gap: FixedPoint::zero().into(),
            },
            info: PoolInfo {
                share_reserves: rng
                    .gen_range(
                        FixedPoint::from(parse_units("1_000", 18).unwrap())
                            ..=FixedPoint::from(parse_units("100_000_000", 18).unwrap()),
                    )
                    .into(),
                bond_reserves: rng
                    .gen_range(
                        FixedPoint::from(parse_units("1_000", 18).unwrap())
                            ..=FixedPoint::from(parse_units("100_000_000", 18).unwrap()),
                    )
                    .into(),
                share_price: rng
                    .gen_range(
                        FixedPoint::from(parse_units("0.5", 18).unwrap())
                            ..=FixedPoint::from(parse_units("2.5", 18).unwrap()),
                    )
                    .into(),
                longs_outstanding: rng
                    .gen_range(
                        FixedPoint::zero()..=FixedPoint::from(parse_units("100_000", 18).unwrap()),
                    )
                    .into(),
                shorts_outstanding: rng
                    .gen_range(
                        FixedPoint::zero()..=FixedPoint::from(parse_units("100_000", 18).unwrap()),
                    )
                    .into(),
                long_average_maturity_time: rng
                    .gen_range(FixedPoint::zero()..=FixedPoint::from(60 * 60 * 24 * 365))
                    .into(),
                short_average_maturity_time: rng
                    .gen_range(FixedPoint::zero()..=FixedPoint::from(60 * 60 * 24 * 365))
                    .into(),
                short_base_volume: rng
                    .gen_range(
                        FixedPoint::zero()..=FixedPoint::from(parse_units("100_000", 18).unwrap()),
                    )
                    .into(),
                lp_total_supply: rng
                    .gen_range(
                        FixedPoint::from(parse_units("1_000", 18).unwrap())
                            ..=FixedPoint::from(parse_units("100_000_000", 18).unwrap()),
                    )
                    .into(),
                // TODO: This should be calculated based on the other values.
                lp_share_price: rng
                    .gen_range(
                        FixedPoint::from(parse_units("0.01", 18).unwrap())
                            ..=FixedPoint::from(parse_units("5", 18).unwrap()),
                    )
                    .into(),
                withdrawal_shares_proceeds: rng
                    .gen_range(
                        FixedPoint::zero()..=FixedPoint::from(parse_units("100_000", 18).unwrap()),
                    )
                    .into(),
                withdrawal_shares_ready_to_withdraw: rng
                    .gen_range(
                        FixedPoint::from(parse_units("1_000", 18).unwrap())
                            ..=FixedPoint::from(parse_units("100_000_000", 18).unwrap()),
                    )
                    .into(),
            },
        }
    }
}

impl State {
    pub fn new(config: PoolConfig, info: PoolInfo) -> Self {
        Self { config, info }
    }

    pub fn get_spot_price(&self) -> FixedPoint {
        YieldSpaceState::from(self).get_spot_price(self.config.time_stretch.into())
    }

    pub fn get_spot_rate(&self) -> FixedPoint {
        let annualized_time = FixedPoint::from(self.config.position_duration)
            / FixedPoint::from(U256::from(60 * 60 * 24 * 365));
        let spot_price = self.get_spot_price();
        (FixedPoint::one() - spot_price) / (spot_price * annualized_time)
    }

    pub fn get_max_long(&self, max_iterations: usize) -> (FixedPoint, FixedPoint) {
        let mut base_amount = FixedPoint::zero();
        let mut bond_amount = FixedPoint::zero();

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
        .mul_div_down(p, FixedPoint::one() - p);
        dy = YieldSpaceState::from(self)
            .get_out_for_in(Asset::Shares(dz), self.config.time_stretch.into());

        // Our maximum long will be the largest trade size that doesn't fail
        // the solvency check.
        for _ in 0..max_iterations {
            // If the approximation error is greater than zero and the solution
            // is the largest we've found so far, then we update our result.
            let approximation_error = I256::from_raw((self.share_reserves() + dz).into())
                - I256::from_raw(((self.longs_outstanding() + dy) / self.share_price()).into())
                - I256::from_raw(self.minimum_share_reserves().into());
            if approximation_error > I256::zero() && dz * self.share_price() > base_amount {
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
            if p >= FixedPoint::one() {
                // If the spot price is greater than one and the error is
                // positive,
                break;
            }
            if approximation_error < I256::zero() {
                let delta = FixedPoint::from((-approximation_error).into_raw())
                    .mul_div_down(p, FixedPoint::one() - p);
                if dz > delta {
                    dz -= delta;
                } else {
                    dz = FixedPoint::zero();
                }
            } else {
                dz += FixedPoint::from(approximation_error.into_raw())
                    .mul_div_down(p, FixedPoint::one() - p);
            }
            dy = YieldSpaceState::from(self)
                .get_out_for_in(Asset::Shares(dz), self.config.time_stretch.into());
        }

        (base_amount, bond_amount)
    }

    pub fn get_max_short(&self) -> FixedPoint {
        // The only constraint on the maximum short is that the share reserves
        // don't go negative and satisfy the solvency requirements. Thus, we can
        // set z = y_l/c + z_min and solve for the maximum short directly as:
        //
        // k = (c / mu) * (mu * (y_l / c + z_min)) ** (1 - tau) + y ** (1 - tau)
        //                         =>
        // y = (k - (c / mu) * (mu * (y_l / c + z_min)) ** (1 - tau)) ** (1 / (1 - tau)).
        let t = FixedPoint::one() - FixedPoint::from(self.config.time_stretch);
        let price_factor = self.share_price() / self.initial_share_price();
        let k = YieldSpaceState::from(self).k(self.config.time_stretch.into());
        let inner_factor = (self.initial_share_price()
            * (self.longs_outstanding() / self.share_price())
            + self.minimum_share_reserves())
        .pow(t);
        let optimal_bond_reserves = (k - price_factor * inner_factor).pow(FixedPoint::one() / t);

        return optimal_bond_reserves - self.bond_reserves();
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
}

#[cfg(test)]
mod tests {
    use super::*;
    use ethers::{
        core::utils::Anvil,
        middleware::SignerMiddleware,
        providers::{Http, Provider},
        signers::{LocalWallet, Signer},
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
            let actual = panic::catch_unwind(|| state.get_max_long(max_iterations));
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
                Ok((expected_base_amount, expected_bond_amount)) => {
                    let (actual_base_amount, actual_bond_amount) = actual.unwrap();
                    assert_eq!(actual_base_amount, FixedPoint::from(expected_base_amount));
                    assert_eq!(actual_bond_amount, FixedPoint::from(expected_bond_amount));
                }
                Err(_) => {
                    let _ = actual.unwrap_err();
                }
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
            let actual = panic::catch_unwind(|| state.get_max_short());
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
                Err(_) => {
                    let _ = actual.unwrap_err();
                }
            }
        }

        Ok(())
    }
}
