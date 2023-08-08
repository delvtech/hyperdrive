use crate::yield_space::State as YieldSpaceState;
use ethers::types::{Address, U256};
use fixed_point::FixedPoint;
use rand::distributions::{Distribution, Standard};
use rand::Rng;
use test_utils::generated::ihyperdrive::{Fees, PoolConfig, PoolInfo};
use test_utils::generated::mock_hyperdrive_math::MaxTradeParams;

#[derive(Debug)]
struct State {
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
                        FixedPoint::from(10_u128.pow(18) / 2)
                            ..=FixedPoint::from(5 * 10_u128.pow(18)),
                    )
                    .into(),
                minimum_share_reserves: rng
                    .gen_range(
                        FixedPoint::from(10_u128.pow(18) / 2)
                            ..=FixedPoint::from(5 * 10_u128.pow(18)),
                    )
                    .into(),
                time_stretch: rng
                    .gen_range(
                        FixedPoint::from(10_u128.pow(18) / 2)
                            ..=FixedPoint::from(5 * 10_u128.pow(18)),
                    )
                    .into(),
                position_duration: rng
                    .gen_range(
                        FixedPoint::from(10_u128.pow(18) / 2)
                            ..=FixedPoint::from(5 * 10_u128.pow(18)),
                    )
                    .into(),
                checkpoint_duration: rng
                    .gen_range(
                        FixedPoint::from(10_u128.pow(18) / 2)
                            ..=FixedPoint::from(5 * 10_u128.pow(18)),
                    )
                    .into(),
                oracle_size: FixedPoint::zero().into(),
                update_gap: FixedPoint::zero().into(),
            },
            info: PoolInfo {
                share_reserves: rng
                    .gen_range(
                        FixedPoint::zero()..=FixedPoint::from(1_000_000_000 * 10_u128.pow(18)),
                    )
                    .into(),
                share_price: rng
                    .gen_range(
                        FixedPoint::zero()..=FixedPoint::from(1_000_000_000 * 10_u128.pow(18)),
                    )
                    .into(),
                bond_reserves: rng
                    .gen_range(
                        FixedPoint::from(10_u128.pow(18) / 2)
                            ..=FixedPoint::from(5 * 10_u128.pow(18)),
                    )
                    .into(),
                longs_outstanding: rng
                    .gen_range(
                        FixedPoint::from(10_u128.pow(18) / 2)
                            ..=FixedPoint::from(5 * 10_u128.pow(18)),
                    )
                    .into(),
                long_average_maturity_time: rng
                    .gen_range(
                        FixedPoint::from(10_u128.pow(18) / 2)
                            ..=FixedPoint::from(5 * 10_u128.pow(18)),
                    )
                    .into(),
                shorts_outstanding: rng
                    .gen_range(
                        FixedPoint::from(10_u128.pow(18) / 2)
                            ..=FixedPoint::from(5 * 10_u128.pow(18)),
                    )
                    .into(),
                short_average_maturity_time: rng
                    .gen_range(
                        FixedPoint::from(10_u128.pow(18) / 2)
                            ..=FixedPoint::from(5 * 10_u128.pow(18)),
                    )
                    .into(),
                short_base_volume: rng
                    .gen_range(
                        FixedPoint::from(10_u128.pow(18) / 2)
                            ..=FixedPoint::from(5 * 10_u128.pow(18)),
                    )
                    .into(),
                lp_total_supply: rng
                    .gen_range(
                        FixedPoint::from(10_u128.pow(18) / 2)
                            ..=FixedPoint::from(5 * 10_u128.pow(18)),
                    )
                    .into(),
                lp_share_price: rng
                    .gen_range(
                        FixedPoint::from(10_u128.pow(18) / 2)
                            ..=FixedPoint::from(5 * 10_u128.pow(18)),
                    )
                    .into(),
                withdrawal_shares_proceeds: rng
                    .gen_range(
                        FixedPoint::from(10_u128.pow(18) / 2)
                            ..=FixedPoint::from(5 * 10_u128.pow(18)),
                    )
                    .into(),
                withdrawal_shares_ready_to_withdraw: rng
                    .gen_range(
                        FixedPoint::from(10_u128.pow(18) / 2)
                            ..=FixedPoint::from(5 * 10_u128.pow(18)),
                    )
                    .into(),
            },
        }
    }
}

impl State {
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

impl State {
    fn new(config: PoolConfig, info: PoolInfo) -> Self {
        Self { config, info }
    }

    pub fn get_spot_price(&self) -> FixedPoint {
        FixedPoint::from(self.config.initial_share_price)
            .mul_div_down(
                self.info.share_reserves.into(),
                self.info.bond_reserves.into(),
            )
            .pow(self.config.time_stretch.into())
    }

    pub fn get_spot_rate(&self) -> FixedPoint {
        let annualized_time = FixedPoint::from(self.config.position_duration)
            / FixedPoint::from(U256::from(60 * 60 * 24 * 365));
        let spot_price = self.get_spot_price();
        (FixedPoint::one() - spot_price) / (spot_price * annualized_time)
    }

    // FIXME
    //
    // fn get_max_long(&self) -> FixedPoint {}

    fn get_max_short(&self) -> FixedPoint {
        // The only constraint on the maximum short is that the share reserves
        // don't go negative and satisfy the solvency requirements. Thus, we can
        // set z = y_l/c + z_min and solve for the maximum short directly as:
        //
        // k = (c / mu) * (mu * (y_l / c + z_min)) ** (1 - tau) + y ** (1 - tau)
        //                         =>
        // y = (k - (c / mu) * (mu * (y_l / c + z_min)) ** (1 - tau)) ** (1 / (1 - tau)).
        let t = FixedPoint::one() - FixedPoint::from(self.config.time_stretch);
        let price_factor = self.share_price() / self.initial_share_price();
        let k = YieldSpaceState::from(self).k(t);
        let inner_factor = (self.initial_share_price()
            * (self.longs_outstanding() / self.share_price())
            + self.minimum_share_reserves())
        .pow(t);
        let optimal_bond_reserves = (k - price_factor * inner_factor).pow(FixedPoint::one() / t);

        return optimal_bond_reserves - self.bond_reserves();
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
    use rand::{thread_rng, Rng};
    use std::{convert::TryFrom, panic, sync::Arc, time::Duration};
    use test_utils::generated::mock_hyperdrive_math::MockHyperdriveMath;

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
