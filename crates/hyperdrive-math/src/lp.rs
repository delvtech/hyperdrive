use ethers::types::{I256, U256};
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, int256};

use crate::{State, YieldSpace};

impl State {
    /// Calculates the present value of LPs capital in the pool.
    pub fn calculate_present_value(&self, current_block_timestamp: U256) -> FixedPoint {
        // Compute the net of the longs and shorts that will be traded on the
        // curve and apply this net to the reserves.
        let long_average_time_remaining = self.time_remaining_scaled(
            current_block_timestamp,
            self.long_average_maturity_time().into(),
        );
        let short_average_time_remaining = self.time_remaining_scaled(
            current_block_timestamp,
            self.short_average_maturity_time().into(),
        );
        let net_curve_trade = I256::from(self.longs_outstanding() * long_average_time_remaining)
            - I256::from(self.shorts_outstanding() * self.short_average_maturity_time().into());
        let present_value = if net_curve_trade > int256!(0) {
            // Close as many longs as possible on the curve. Any longs that
            // can't be closed will be stuck until maturity (assuming nothing
            // changes) at which time the longs will receive the bond's face
            // value and the LPs will receive any variable interest that is
            // collected. It turns out that the value that we place on these
            // stuck longs doesn't have an impact on LP fairness since longs
            // are only stuck when there is no idle remaining. With this in
            // mind, we mark the longs to zero for simplicity and to avoid
            // unnecessary computation.
            let mut max_curve_trade = self.calculate_max_sell(self.minimum_share_reserves());
            max_curve_trade = max_curve_trade.min(net_curve_trade.into());
            if max_curve_trade > fixed!(0) {
                // NOTE: We underestimate here to match the behavior of `calculateCloseLong`.
                self.share_reserves()
                    - self.calculate_shares_out_given_bonds_in_down(max_curve_trade)
            } else {
                fixed!(0)
            }
        } else {
            // Close as many shorts as possible on the curve. Any shorts that
            // can't be closed will be stuck until maturity (assuming nothing
            // changes) at which time the LPs will receive the bond's face
            // value. If we value the stuck shorts at less than the face value,
            // LPs that remove liquidity before liquidity will receive a smaller
            // amount of withdrawal shares than they should. On the other hand,
            // if we value the stuck shorts at more than the face value, LPs
            // that remove liquidity before maturity will receive a larger
            // amount of withdrawal shares than they should. With this in mind,
            // we value the stuck shorts at exactly the face value.
            let max_curve_trade = self.calculate_max_buy().min((-net_curve_trade).into()); // netCurveTrade is positive, so this is safe.
            if max_curve_trade > fixed!(0) {
                // NOTE: We overestimate here to match the behavior of
                // `calculateCloseShort`.
                self.share_reserves() + self.calculate_shares_in_given_bonds_out_up(max_curve_trade)
            } else {
                fixed!(0)
            }
        };

        // Compute the net of the longs and shorts that will be traded flat and
        // apply this net to the reserves.
        let net_flat_trade = I256::from(self.shorts_outstanding().mul_div_down(
            fixed!(1e18) - short_average_time_remaining,
            self.share_price(),
        )) - I256::from(self.longs_outstanding().mul_div_down(
            fixed!(1e18) - long_average_time_remaining,
            self.share_price(),
        ));
        let updated_share_reserves = I256::from(present_value) + net_flat_trade;
        if updated_share_reserves < I256::from(self.minimum_share_reserves()) {
            panic!("Negative present value!");
        }

        // The present value is the final share reserves minus the minimum share
        // reserves. This ensures that LP withdrawals won't include the minimum
        // share reserves.
        FixedPoint::from(updated_share_reserves) - self.minimum_share_reserves()
    }
}

#[cfg(test)]
mod tests {
    use std::panic;

    use ethers::types::U256;
    use eyre::Result;
    use fixed_point_macros::uint256;
    use hyperdrive_wrappers::wrappers::mock_hyperdrive_math::PresentValueParams;
    use rand::{thread_rng, Rng};
    use test_utils::{
        agent::Agent,
        chain::{Chain, TestChain, TestChainWithMocks},
        constants::{FAST_FUZZ_RUNS, FUZZ_RUNS},
    };
    use tracing_test::traced_test;

    use super::*;
    use crate::get_effective_share_reserves;

    /// This test differentially fuzzes the `absolute_max_long` function against
    /// the Solidity analogue `calculateAbsoluteMaxLong`.
    #[tokio::test]
    async fn fuzz_calculate_present_value() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_hyperdrive_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let current_block_timestamp = rng.gen();
            let actual =
                panic::catch_unwind(|| state.calculate_present_value(current_block_timestamp));
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
                    long_average_time_remaining: self.time_remaining_scaled(
                        current_block_timestamp,
                        self.long_average_maturity_time().into(),
                    ),
                    short_average_time_remaining: self.time_remaining_scaled(
                        current_block_timestamp,
                        self.short_average_maturity_time().into(),
                    ),
                    shorts_outstanding: state.shorts_outstanding(),
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
