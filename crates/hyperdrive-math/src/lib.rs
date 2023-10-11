mod long;
mod short;
mod utils;
mod yield_space;

use ethers::types::{Address, I256, U256};
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, uint256};
use hyperdrive_wrappers::wrappers::i_hyperdrive::{Fees, PoolConfig, PoolInfo};
use rand::{
    distributions::{Distribution, Standard},
    Rng,
};
pub use utils::*;
use yield_space::YieldSpace;

#[derive(Debug, PartialEq, Eq, PartialOrd, Ord, Clone, Copy)]
pub enum Asset {
    Shares(FixedPoint),
    Bonds(FixedPoint),
}

impl Distribution<Asset> for Standard {
    fn sample<R: Rng + ?Sized>(&self, rng: &mut R) -> Asset {
        let content = rng.gen::<FixedPoint>();
        if rng.gen::<bool>() {
            Asset::Shares(content)
        } else {
            Asset::Bonds(content)
        }
    }
}

#[derive(Debug)]
pub struct State {
    pub config: PoolConfig,
    pub info: PoolInfo,
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
            minimum_transaction_amount: rng.gen_range(fixed!(0.1e18)..=fixed!(1e18)).into(),
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
            token_decimals: 18,
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
            long_exposure: rng.gen_range(fixed!(0)..=fixed!(100_000e18)).into(),
            share_adjustment: {
                if rng.gen() {
                    -I256::from(rng.gen_range(fixed!(0)..=fixed!(100_000e18)))
                } else {
                    // We generate values that satisfy `z - zeta >= z_min`,
                    // so `z - z_min >= zeta`.
                    I256::from(rng.gen_range(
                        fixed!(0)
                            ..(share_reserves - FixedPoint::from(config.minimum_share_reserves)),
                    ))
                }
            },
            long_average_maturity_time: rng
                .gen_range(fixed!(0)..=FixedPoint::from(60 * 60 * 24 * 365))
                .into(),
            short_average_maturity_time: rng
                .gen_range(fixed!(0)..=FixedPoint::from(60 * 60 * 24 * 365))
                .into(),
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
        YieldSpace::get_spot_price(self)
    }

    /// Gets the pool's spot rate.
    pub fn get_spot_rate(&self) -> FixedPoint {
        let annualized_time =
            self.position_duration() / FixedPoint::from(U256::from(60 * 60 * 24 * 365));
        let spot_price = self.get_spot_price();
        (fixed!(1e18) - spot_price) / (spot_price * annualized_time)
    }

    /// Converts a timestamp to the checkpoint timestamp that it corresponds to.
    pub fn to_checkpoint(&self, time: U256) -> U256 {
        time - time % self.config.checkpoint_duration
    }

    /// Config ///

    fn position_duration(&self) -> FixedPoint {
        self.config.position_duration.into()
    }

    fn checkpoint_duration(&self) -> FixedPoint {
        self.config.checkpoint_duration.into()
    }

    fn time_stretch(&self) -> FixedPoint {
        self.config.time_stretch.into()
    }

    fn initial_share_price(&self) -> FixedPoint {
        self.config.initial_share_price.into()
    }

    fn minimum_share_reserves(&self) -> FixedPoint {
        self.config.minimum_share_reserves.into()
    }

    fn curve_fee(&self) -> FixedPoint {
        self.config.fees.curve.into()
    }

    fn flat_fee(&self) -> FixedPoint {
        self.config.fees.flat.into()
    }

    fn governance_fee(&self) -> FixedPoint {
        self.config.fees.governance.into()
    }

    /// Info ///

    fn share_price(&self) -> FixedPoint {
        self.info.share_price.into()
    }

    fn share_reserves(&self) -> FixedPoint {
        self.info.share_reserves.into()
    }

    fn effective_share_reserves(&self) -> FixedPoint {
        get_effective_share_reserves(self.share_reserves(), self.share_adjustment())
    }

    fn bond_reserves(&self) -> FixedPoint {
        self.info.bond_reserves.into()
    }

    fn longs_outstanding(&self) -> FixedPoint {
        self.info.longs_outstanding.into()
    }

    fn shorts_outstanding(&self) -> FixedPoint {
        self.info.shorts_outstanding.into()
    }

    fn long_exposure(&self) -> FixedPoint {
        self.info.long_exposure.into()
    }

    fn share_adjustment(&self) -> I256 {
        self.info.share_adjustment.into()
    }
}

impl YieldSpace for State {
    fn z(&self) -> FixedPoint {
        self.effective_share_reserves()
    }

    fn y(&self) -> FixedPoint {
        self.bond_reserves()
    }

    fn mu(&self) -> FixedPoint {
        self.initial_share_price()
    }

    fn c(&self) -> FixedPoint {
        self.share_price()
    }

    fn t(&self) -> FixedPoint {
        self.time_stretch()
    }
}
