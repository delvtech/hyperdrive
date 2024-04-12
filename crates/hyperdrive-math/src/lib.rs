mod long;
mod lp;
mod short;
mod utils;
mod yield_space;

use ethers::types::{Address, I256, U256};
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;
use hyperdrive_wrappers::wrappers::ihyperdrive::{Fees, PoolConfig, PoolInfo};
use rand::{
    distributions::{Distribution, Standard},
    Rng,
};
pub use utils::*;
pub use yield_space::YieldSpace;

#[derive(Clone, Debug)]
pub struct State {
    pub config: PoolConfig,
    pub info: PoolInfo,
}

impl Distribution<State> for Standard {
    // TODO: It may be better for this to be a uniform sampler and have a test
    // sampler that is more restrictive like this.
    fn sample<R: Rng + ?Sized>(&self, rng: &mut R) -> State {
        let one_day_in_seconds = 60 * 60 * 24;
        let one_hour_in_seconds = 60 * 60;

        let config = PoolConfig {
            base_token: Address::zero(),
            vault_shares_token: Address::zero(),
            linker_factory: Address::zero(),
            linker_code_hash: [0; 32],
            governance: Address::zero(),
            fee_collector: Address::zero(),
            sweep_collector: Address::zero(),
            fees: Fees {
                curve: rng.gen_range(fixed!(0.0001e18)..=fixed!(0.2e18)).into(),
                flat: rng.gen_range(fixed!(0.0001e18)..=fixed!(0.2e18)).into(),
                governance_lp: rng.gen_range(fixed!(0.0001e18)..=fixed!(0.2e18)).into(),
                governance_zombie: rng.gen_range(fixed!(0.0001e18)..=fixed!(0.2e18)).into(),
            },
            initial_vault_share_price: rng.gen_range(fixed!(0.5e18)..=fixed!(2.5e18)).into(),
            minimum_share_reserves: rng.gen_range(fixed!(0.1e18)..=fixed!(1e18)).into(),
            minimum_transaction_amount: rng.gen_range(fixed!(0.1e18)..=fixed!(1e18)).into(),
            time_stretch: rng.gen_range(fixed!(0.005e18)..=fixed!(0.5e18)).into(),
            position_duration: rng
                .gen_range(
                    FixedPoint::from(91 * one_day_in_seconds)
                        ..=FixedPoint::from(365 * one_day_in_seconds),
                )
                .into(),
            checkpoint_duration: rng
                .gen_range(
                    FixedPoint::from(one_hour_in_seconds)..=FixedPoint::from(one_day_in_seconds),
                )
                .into(),
        };
        // We need the spot price to be less than or equal to 1, so we need to
        // generate the bond reserves so that mu * z <= y
        let share_reserves = rng.gen_range(fixed!(1_000e18)..=fixed!(100_000_000e18));
        let info = PoolInfo {
            share_reserves: share_reserves.into(),
            zombie_base_proceeds: fixed!(0).into(),
            zombie_share_reserves: fixed!(0).into(),
            bond_reserves: rng
                .gen_range(
                    share_reserves * FixedPoint::from(config.initial_vault_share_price)
                        ..=fixed!(1_000_000_000e18),
                )
                .into(),
            vault_share_price: rng.gen_range(fixed!(0.5e18)..=fixed!(2.5e18)).into(),
            longs_outstanding: rng.gen_range(fixed!(0)..=fixed!(100_000e18)).into(),
            shorts_outstanding: rng.gen_range(fixed!(0)..=fixed!(100_000e18)).into(),
            long_exposure: rng.gen_range(fixed!(0)..=fixed!(100_000e18)).into(),
            share_adjustment: {
                if rng.gen() {
                    -I256::try_from(rng.gen_range(fixed!(0)..=fixed!(100_000e18))).unwrap()
                } else {
                    // We generate values that satisfy `z - zeta >= z_min`,
                    // so `z - z_min >= zeta`.
                    I256::try_from(rng.gen_range(
                        fixed!(0)
                            ..(share_reserves - FixedPoint::from(config.minimum_share_reserves)),
                    ))
                    .unwrap()
                }
            },
            // If this range returns greater than position duration, then both rust and solidity will fail
            // on calls that depend on this value.
            long_average_maturity_time: rng
                .gen_range(fixed!(0)..=FixedPoint::from(365 * one_day_in_seconds) * fixed!(1e18))
                .into(),
            short_average_maturity_time: rng
                .gen_range(fixed!(0)..=FixedPoint::from(365 * one_day_in_seconds) * fixed!(1e18))
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

    /// Calculates the pool's spot price.
    pub fn calculate_spot_price(&self) -> FixedPoint {
        YieldSpace::calculate_spot_price(self)
    }

    /// Calculate the pool's current spot (aka "fixed") rate.
    pub fn calculate_spot_rate(&self) -> FixedPoint {
        calculate_rate_given_fixed_price(self.calculate_spot_price(), self.position_duration())
    }

    /// Converts a timestamp to the checkpoint timestamp that it corresponds to.
    pub fn to_checkpoint(&self, time: U256) -> U256 {
        time - time % self.config.checkpoint_duration
    }

    /// Calculates the normalized time remaining
    fn calculate_normalized_time_remaining(
        &self,
        maturity_time: U256,
        current_time: U256,
    ) -> FixedPoint {
        let latest_checkpoint = self.to_checkpoint(current_time);
        if maturity_time > latest_checkpoint {
            // NOTE: Round down to underestimate the time remaining.
            FixedPoint::from(maturity_time - latest_checkpoint).div_down(self.position_duration())
        } else {
            fixed!(0)
        }
    }

    /// Calculates the pool reserve levels to achieve a target interest rate.
    /// This calculation does not take Hyperdrive's solvency constraints or exposure
    /// into account and shouldn't be used directly.
    ///
    /// The price for a given fixed-rate is given by $p = 1 / (r \cdot t + 1)$, where
    /// $r$ is the fixed-rate and $t$ is the annualized position duration. The
    /// price for a given pool reserves is given by $p = \frac{\mu z}{y}^t_{s}$,
    /// where $\mu$ is the initial share price and $t_{s}$ is the time stretch
    /// constant. By setting these equal we can solve for the pool reserve levels
    /// as a function of a target rate.
    ///
    /// For some target rate, $r_t$, the pool share reserves, $z_t$, must be:
    ///
    /// $$
    /// z_t = \frac{1}{\mu} \left(
    ///   \frac{k}{\frac{c}{\mu} + \left(
    ///     (r_t \cdot t + 1)^{\frac{1}{t_{s}}}
    ///   \right)^{1 - t_{s}}}
    /// \right)^{\tfrac{1}{1 - t_{s}}}
    /// $$
    ///
    /// and the pool bond reserves, $y_t$, must be:
    ///
    /// $$
    /// y_t = \left(
    ///   \frac{k}{ \frac{c}{\mu} +  \left(
    ///     \left( r_t \cdot t + 1 \right)^{\frac{1}{t_{s}}}
    ///   \right)^{1 - t_{s}}}
    /// \right)^{1 - t_{s}} \left( r_t t + 1 \right)^{\frac{1}{t_{s}}}
    /// $$
    fn reserves_given_rate_ignoring_exposure<F: Into<FixedPoint>>(
        &self,
        target_rate: F,
    ) -> (FixedPoint, FixedPoint) {
        let target_rate = target_rate.into();

        // First get the target share reserves
        let c_over_mu = self
            .vault_share_price()
            .div_up(self.initial_vault_share_price());
        let scaled_rate = (target_rate.mul_up(self.annualized_position_duration()) + fixed!(1e18))
            .pow(fixed!(1e18) / self.time_stretch());
        let inner = (self.k_down()
            / (c_over_mu + scaled_rate.pow(fixed!(1e18) - self.time_stretch())))
        .pow(fixed!(1e18) / (fixed!(1e18) - self.time_stretch()));
        let target_share_reserves = inner / self.initial_vault_share_price();

        // Then get the target bond reserves.
        let target_bond_reserves = inner * scaled_rate;

        (target_share_reserves, target_bond_reserves)
    }

    /// Config ///

    fn position_duration(&self) -> FixedPoint {
        self.config.position_duration.into()
    }

    fn annualized_position_duration(&self) -> FixedPoint {
        self.position_duration() / FixedPoint::from(U256::from(60 * 60 * 24 * 365))
    }

    fn checkpoint_duration(&self) -> FixedPoint {
        self.config.checkpoint_duration.into()
    }

    fn time_stretch(&self) -> FixedPoint {
        self.config.time_stretch.into()
    }

    fn initial_vault_share_price(&self) -> FixedPoint {
        self.config.initial_vault_share_price.into()
    }

    fn minimum_share_reserves(&self) -> FixedPoint {
        self.config.minimum_share_reserves.into()
    }

    fn minimum_transaction_amount(&self) -> FixedPoint {
        self.config.minimum_transaction_amount.into()
    }

    fn curve_fee(&self) -> FixedPoint {
        self.config.fees.curve.into()
    }

    fn flat_fee(&self) -> FixedPoint {
        self.config.fees.flat.into()
    }

    fn governance_lp_fee(&self) -> FixedPoint {
        self.config.fees.governance_lp.into()
    }

    /// Info ///

    fn vault_share_price(&self) -> FixedPoint {
        self.info.vault_share_price.into()
    }

    fn share_reserves(&self) -> FixedPoint {
        self.info.share_reserves.into()
    }

    fn effective_share_reserves(&self) -> FixedPoint {
        calculate_effective_share_reserves(self.share_reserves(), self.share_adjustment())
    }

    fn bond_reserves(&self) -> FixedPoint {
        self.info.bond_reserves.into()
    }

    fn longs_outstanding(&self) -> FixedPoint {
        self.info.longs_outstanding.into()
    }

    fn long_average_maturity_time(&self) -> FixedPoint {
        self.info.long_average_maturity_time.into()
    }

    fn shorts_outstanding(&self) -> FixedPoint {
        self.info.shorts_outstanding.into()
    }

    fn short_average_maturity_time(&self) -> FixedPoint {
        self.info.short_average_maturity_time.into()
    }

    fn long_exposure(&self) -> FixedPoint {
        self.info.long_exposure.into()
    }

    fn share_adjustment(&self) -> I256 {
        self.info.share_adjustment
    }

    fn lp_total_supply(&self) -> FixedPoint {
        self.info.lp_total_supply.into()
    }

    fn withdrawal_shares_proceeds(&self) -> FixedPoint {
        self.info.withdrawal_shares_proceeds.into()
    }

    fn withdrawal_shares_ready_to_withdraw(&self) -> FixedPoint {
        self.info.withdrawal_shares_ready_to_withdraw.into()
    }
}

impl YieldSpace for State {
    fn z(&self) -> FixedPoint {
        self.share_reserves()
    }

    fn zeta(&self) -> I256 {
        self.share_adjustment()
    }

    fn y(&self) -> FixedPoint {
        self.bond_reserves()
    }

    fn mu(&self) -> FixedPoint {
        self.initial_vault_share_price()
    }

    fn c(&self) -> FixedPoint {
        self.vault_share_price()
    }

    fn t(&self) -> FixedPoint {
        self.time_stretch()
    }
}

#[cfg(test)]
mod tests {
    use eyre::Result;
    use rand::thread_rng;

    use super::*;

    #[tokio::test]
    async fn test_calculate_normalized_time_remaining() -> Result<()> {
        // TODO: fuzz test against calculateTimeRemaining in MockHyperdrive.sol
        let mut rng = thread_rng();
        let mut state = rng.gen::<State>();

        // Set a snapshot for the values used for calculating normalized time
        // remaining
        state.config.position_duration = fixed!(28209717).into();
        state.config.checkpoint_duration = fixed!(43394).into();
        let expected_time_remaining = fixed!(3544877816392);

        let maturity_time = U256::from(100);
        let current_time = U256::from(90);
        let time_remaining = state.calculate_normalized_time_remaining(maturity_time, current_time);

        assert_eq!(expected_time_remaining, time_remaining);
        Ok(())
    }
}
