use ethers::types::{I256, U256};
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, int256};

use crate::{State, YieldSpace};

impl State {
    /// Calculates the present value of LPs capital in the pool.
    pub fn calculate_present_value(&self, current_block_timestamp: U256) -> FixedPoint {
        // Calculate the average time remaining for the longs and shorts.
        let long_average_time_remaining = self.time_remaining_scaled(
            current_block_timestamp,
            self.long_average_maturity_time().into(),
        );
        let short_average_time_remaining = self.time_remaining_scaled(
            current_block_timestamp,
            self.short_average_maturity_time().into(),
        );

        let present_value: I256 = I256::from(self.share_reserves())
            + self.calculate_net_curve_trade(
                long_average_time_remaining,
                short_average_time_remaining,
            )
            + self.calculate_net_flat_trade(
                long_average_time_remaining,
                short_average_time_remaining,
            )
            - I256::from(self.minimum_share_reserves());

        if present_value < int256!(0) {
            panic!("Negative present value!");
        }
        present_value.into()
    }

    pub fn calculate_net_curve_trade(
        &self,
        long_average_time_remaining: FixedPoint,
        short_average_time_remaining: FixedPoint,
    ) -> I256 {
        // The net curve position is the net of the longs and shorts that are
        // currently tradeable on the curve. Given the amount of outstanding
        // longs `y_l` and shorts `y_s` as well as the average time remaining
        // of outstanding longs `t_l` and shorts `t_s`, we can
        // compute the net curve position as:
        //
        // netCurveTrade = y_l * t_l - y_s * t_s.
        let net_curve_position: I256 = I256::from(
            self.longs_outstanding()
                .mul_down(long_average_time_remaining),
        ) - I256::from(
            self.shorts_outstanding()
                .mul_down(short_average_time_remaining),
        );

        // If the net curve position is positive, then the pool is net long.
        // Closing the net curve position results in the longs being paid out
        // from the share reserves, so we negate the result.
        let result: I256 = if net_curve_position > int256!(0) {
            // Calculate the maximum amount of bonds that can be sold on
            // YieldSpace.
            let max_curve_trade =
                self.calculate_max_sell_bonds_in(self.minimum_share_reserves());
            // If the max curve trade is greater than the net curve position,
            // then we can close the entire net curve position.
            if max_curve_trade >= net_curve_position.into() {
                -I256::from(
                    self.calculate_shares_out_given_bonds_in_down(net_curve_position.into()),
                )
            } else {
                // Otherwise, we can only close part of the net curve position.
                // Since the spot price is approximately zero after closing the
                // entire net curve position, we mark any remaining bonds to zero.
                -I256::from(self.effective_share_reserves() - self.minimum_share_reserves())
            }
        } else if net_curve_position < int256!(0) {
            let _net_curve_position: FixedPoint = FixedPoint::from(-net_curve_position);
            // Calculate the maximum amount of bonds that can be bought on
            // YieldSpace.
            let max_curve_trade = self.calculate_max_buy_bonds_out();
            if max_curve_trade >= _net_curve_position {
                I256::from(
                    self.calculate_shares_in_given_bonds_out_up(_net_curve_position),
                )
            } else {
                let max_share_payment = self.calculate_max_buy_shares_in();
                I256::from(
                    max_share_payment
                        + (_net_curve_position - max_curve_trade).div_down(self.share_price()),
                )
            }
        } else {
            int256!(0)
        };
        result
    }

    pub fn calculate_net_flat_trade(
        &self,
        long_average_time_remaining: FixedPoint,
        short_average_time_remaining: FixedPoint,
    ) -> I256 {
        // Compute the net of the longs and shorts that will be traded flat and
        // apply this net to the reserves.
        I256::from(self.shorts_outstanding().mul_div_down(
            fixed!(1e18) - short_average_time_remaining,
            self.share_price(),
        )) - I256::from(self.longs_outstanding().mul_div_down(
            fixed!(1e18) - long_average_time_remaining,
            self.share_price(),
        ))
    }
}

#[cfg(test)]
mod tests {
    use std::panic;

    use eyre::Result;
    use hyperdrive_wrappers::wrappers::mock_hyperdrive_math::PresentValueParams;
    use rand::{thread_rng, Rng};
    use test_utils::{chain::TestChainWithMocks, constants::FAST_FUZZ_RUNS};

    use super::*;

    #[tokio::test]
    async fn fuzz_calculate_present_value() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_hyperdrive_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let current_block_timestamp = rng.gen_range(fixed!(1)..=fixed!(1e4));
            let actual = panic::catch_unwind(|| {
                state.calculate_present_value(current_block_timestamp.into())
            });
            match mock
                .calculate_present_value(PresentValueParams {
                    share_reserves: state.info.share_reserves,
                    bond_reserves: state.info.bond_reserves,
                    longs_outstanding: state.info.longs_outstanding,
                    share_adjustment: state.info.share_adjustment,
                    time_stretch: state.config.time_stretch,
                    share_price: state.info.share_price,
                    initial_share_price: state.config.initial_share_price,
                    minimum_share_reserves: state.config.minimum_share_reserves,
                    long_average_time_remaining: state
                        .time_remaining_scaled(
                            current_block_timestamp.into(),
                            state.long_average_maturity_time().into(),
                        )
                        .into(),
                    short_average_time_remaining: state
                        .time_remaining_scaled(
                            current_block_timestamp.into(),
                            state.short_average_maturity_time().into(),
                        )
                        .into(),
                    shorts_outstanding: state.shorts_outstanding().into(),
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
    async fn fuzz_calculate_net_curve_trade() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_hyperdrive_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let current_block_timestamp = rng.gen_range(fixed!(1)..=fixed!(1e4));
            let long_average_time_remaining = state.time_remaining_scaled(
                current_block_timestamp.into(),
                state.long_average_maturity_time().into(),
            );
            let short_average_time_remaining = state.time_remaining_scaled(
                current_block_timestamp.into(),
                state.short_average_maturity_time().into(),
            );
            let actual = panic::catch_unwind(|| {
                state.calculate_net_curve_trade(
                    long_average_time_remaining,
                    short_average_time_remaining,
                )
            });
            match mock
                .calculate_net_curve_trade(PresentValueParams {
                    share_reserves: state.info.share_reserves,
                    bond_reserves: state.info.bond_reserves,
                    longs_outstanding: state.info.longs_outstanding,
                    share_adjustment: state.info.share_adjustment,
                    time_stretch: state.config.time_stretch,
                    share_price: state.info.share_price,
                    initial_share_price: state.config.initial_share_price,
                    minimum_share_reserves: state.config.minimum_share_reserves,
                    long_average_time_remaining: long_average_time_remaining.into(),
                    short_average_time_remaining: short_average_time_remaining.into(),
                    shorts_outstanding: state.shorts_outstanding().into(),
                })
                .call()
                .await
            {
                Ok(expected) => {
                    assert_eq!(actual.unwrap(), I256::from(expected));
                }
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_calculate_net_flat_trade() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_hyperdrive_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let current_block_timestamp = rng.gen_range(fixed!(1)..=fixed!(1e4));
            let long_average_time_remaining = state.time_remaining_scaled(
                current_block_timestamp.into(),
                state.long_average_maturity_time().into(),
            );
            let short_average_time_remaining = state.time_remaining_scaled(
                current_block_timestamp.into(),
                state.short_average_maturity_time().into(),
            );
            let actual = panic::catch_unwind(|| {
                state.calculate_net_flat_trade(
                    long_average_time_remaining,
                    short_average_time_remaining,
                )
            });
            match mock
                .calculate_net_flat_trade(PresentValueParams {
                    share_reserves: state.info.share_reserves,
                    bond_reserves: state.info.bond_reserves,
                    longs_outstanding: state.info.longs_outstanding,
                    share_adjustment: state.info.share_adjustment,
                    time_stretch: state.config.time_stretch,
                    share_price: state.info.share_price,
                    initial_share_price: state.config.initial_share_price,
                    minimum_share_reserves: state.config.minimum_share_reserves,
                    long_average_time_remaining: long_average_time_remaining.into(),
                    short_average_time_remaining: short_average_time_remaining.into(),
                    shorts_outstanding: state.shorts_outstanding().into(),
                })
                .call()
                .await
            {
                Ok(expected) => {
                    assert_eq!(actual.unwrap(), I256::from(expected));
                }
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }
}
