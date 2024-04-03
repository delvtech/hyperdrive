use std::cmp::{max, Ordering};

use ethers::types::{I256, U256};
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, int256};

use crate::{get_effective_share_reserves, State, YieldSpace};

impl State {
    /// Calculates the number of base that are not reserved by open positions.
    pub fn calculate_idle_share_reserves_in_base(&self) -> FixedPoint {
        // NOTE: Round up to underestimate the pool's idle.
        let long_exposure = self.long_exposure().div_up(self.vault_share_price());

        // Calculate the idle base reserves.
        let mut idle_shares_in_base = fixed!(0);
        if self.share_reserves() > (long_exposure + self.minimum_share_reserves()) {
            idle_shares_in_base =
                (self.share_reserves() - long_exposure - self.minimum_share_reserves())
                    * self.vault_share_price();
        }

        idle_shares_in_base
    }

    /// Calculates the present value of LPs capital in the pool.
    pub fn calculate_present_value(&self, current_block_timestamp: U256) -> FixedPoint {
        // Calculate the average time remaining for the longs and shorts.
        let long_average_time_remaining = self.calculate_normalized_time_remaining(
            self.long_average_maturity_time().into(),
            current_block_timestamp,
        );
        let short_average_time_remaining = self.calculate_normalized_time_remaining(
            self.short_average_maturity_time().into(),
            current_block_timestamp,
        );

        let present_value: I256 = I256::try_from(self.share_reserves()).unwrap()
            + self.calculate_net_curve_trade(
                long_average_time_remaining,
                short_average_time_remaining,
            )
            + self.calculate_net_flat_trade(
                long_average_time_remaining,
                short_average_time_remaining,
            )
            - I256::try_from(self.minimum_share_reserves()).unwrap();

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
        // NOTE: To underestimate the impact of closing the net curve position,
        // we round up the long side of the net curve position (since this
        // results in a larger value removed from the share reserves) and round
        // down the short side of the net curve position (since this results in
        // a smaller value added to the share reserves).
        //
        // The net curve position is the net of the longs and shorts that are
        // currently tradeable on the curve. Given the amount of outstanding
        // longs `y_l` and shorts `y_s` as well as the average time remaining
        // of outstanding longs `t_l` and shorts `t_s`, we can
        // compute the net curve position as:
        //
        // netCurveTrade = y_l * t_l - y_s * t_s.
        let net_curve_position: I256 =
            I256::try_from(self.longs_outstanding().mul_up(long_average_time_remaining)).unwrap()
                - I256::try_from(
                    self.shorts_outstanding()
                        .mul_down(short_average_time_remaining),
                )
                .unwrap();

        // If the net curve position is positive, then the pool is net long.
        // Closing the net curve position results in the longs being paid out
        // from the share reserves, so we negate the result.
        match net_curve_position.cmp(&int256!(0)) {
            Ordering::Greater => {
                let net_curve_position: FixedPoint = FixedPoint::from(net_curve_position);
                let max_curve_trade = self
                    .calculate_max_sell_bonds_in_safe(self.minimum_share_reserves())
                    .unwrap();
                if max_curve_trade >= net_curve_position.into() {
                    match self
                        .calculate_shares_out_given_bonds_in_down_safe(net_curve_position.into())
                    {
                        Ok(net_curve_trade) => -I256::try_from(net_curve_trade).unwrap(),
                        Err(err) => {
                            // If the net curve position is smaller than the
                            // minimum transaction amount and the trade fails,
                            // we mark it to 0. This prevents liveness problems
                            // when the net curve position is very small.
                            if net_curve_position < self.minimum_transaction_amount() {
                                I256::zero()
                            } else {
                                panic!("net_curve_trade failure: {}", err);
                            }
                        }
                    }
                } else {
                    // If the share adjustment is greater than or equal to zero,
                    // then the effective share reserves are less than or equal to
                    // the share reserves. In this case, the maximum amount of
                    // shares that can be removed from the share reserves is
                    // `effectiveShareReserves - minimumShareReserves`.
                    if self.share_adjustment() >= I256::from(0) {
                        -I256::try_from(
                            self.effective_share_reserves() - self.minimum_share_reserves(),
                        )
                        .unwrap()

                    // Otherwise, the effective share reserves are greater than the
                    // share reserves. In this case, the maximum amount of shares
                    // that can be removed from the share reserves is
                    // `shareReserves - minimumShareReserves`.
                    } else {
                        -I256::try_from(self.share_reserves() - self.minimum_share_reserves())
                            .unwrap()
                    }
                }
            }
            Ordering::Less => {
                let net_curve_position: FixedPoint = FixedPoint::from(-net_curve_position);
                let max_curve_trade = self.calculate_max_buy_bonds_out_safe().unwrap();
                if max_curve_trade >= net_curve_position {
                    match self
                        .calculate_shares_in_given_bonds_out_up_safe(net_curve_position.into())
                    {
                        Ok(net_curve_trade) => I256::try_from(net_curve_trade).unwrap(),
                        Err(err) => {
                            // If the net curve position is smaller than the
                            // minimum transaction amount and the trade fails,
                            // we mark it to 0. This prevents liveness problems
                            // when the net curve position is very small.
                            if net_curve_position < self.minimum_transaction_amount() {
                                I256::zero()
                            } else {
                                panic!("net_curve_trade failure: {}", err);
                            }
                        }
                    }
                } else {
                    let max_share_payment = self.calculate_max_buy_shares_in_safe().unwrap();

                    // NOTE: We round the difference down to underestimate the
                    // impact of closing the net curve position.
                    I256::try_from(
                        max_share_payment
                            + (net_curve_position - max_curve_trade)
                                .div_down(self.vault_share_price()),
                    )
                    .unwrap()
                }
            }
            Ordering::Equal => int256!(0),
        }
    }

    pub fn calculate_net_flat_trade(
        &self,
        long_average_time_remaining: FixedPoint,
        short_average_time_remaining: FixedPoint,
    ) -> I256 {
        // NOTE: In order to underestimate the impact of closing all of the
        // flat trades, we round the impact of closing the shorts down and round
        // the impact of closing the longs up.
        //
        // Compute the net of the longs and shorts that will be traded flat and
        // apply this net to the reserves.
        I256::try_from(self.shorts_outstanding().mul_div_down(
            fixed!(1e18) - short_average_time_remaining,
            self.vault_share_price(),
        ))
        .unwrap()
            - I256::try_from(self.longs_outstanding().mul_div_up(
                fixed!(1e18) - long_average_time_remaining,
                self.vault_share_price(),
            ))
            .unwrap()
    }

    pub fn calculate_add_liquidity(
        &self,
        current_block_timestamp: U256,
        contribution: FixedPoint,
        min_apr: Option<FixedPoint>,
        max_apr: Option<FixedPoint>,
    ) -> Result<FixedPoint, &str> {
        // Ensure that the contribution is greater than or equal to the minimum
        // transaction amount.
        if contribution < self.minimum_transaction_amount() {
            return Err("MinimumTransactionAmount");
        }

        // Enforce the slippage guard.
        if min_apr.is_some() && max_apr.is_some() {
            let apr = self.get_spot_rate();
            let invalid_apr = apr < min_apr.unwrap() || apr > max_apr.unwrap();
            if invalid_apr {
                return Err("InvalidApr");
            }
        }

        // Get withdraw_shares_outstanding and lp_total_supply for the lp_shares calculation.
        let withdraw_shares_outstanding =
            self.withdrawal_shares_proceeds() - self.withdrawal_shares_ready_to_withdraw();
        let lp_total_supply = self.lp_total_supply() - withdraw_shares_outstanding;

        // Get the starting_present_value.
        let starting_present_value = self.calculate_present_value(current_block_timestamp);

        // Get the ending_present_value.
        let share_contribution = I256::try_from(contribution * self.vault_share_price()).unwrap();
        let new_state = self.update_liquidity(share_contribution);
        let ending_present_value = new_state.calculate_present_value(current_block_timestamp);

        // Ensure the present value didn't decreased after adding liquidity.
        if ending_present_value < starting_present_value {
            return Err("DecreasedPresentValueWhenAddingLiquidity");
        }

        // Calculate the lp_shares.
        let lp_shares = (ending_present_value - starting_present_value)
            .mul_div_down(lp_total_supply, starting_present_value);

        // Ensure that enough lp_shares are minted so that they can be redeemed.
        if lp_shares < self.minimum_transaction_amount() {
            return Err("MinimumTransactionAmount");
        }

        // TODO: add the solidity _distributeExcessIdleSafe check here.

        return Ok(lp_shares);
    }

    fn update_liquidity(&self, share_reserves_delta: I256) -> State {
        let share_reserves = self.share_reserves();
        let share_adjustment = self.share_adjustment();
        let bond_reserves = self.bond_reserves();
        let minimum_share_reserves = self.minimum_share_reserves();

        // Calculate new reserve and adjustment levels.
        let (updated_share_reserves, updated_share_adjustment, updated_bond_reserves) = self
            .calculate_update_liquidity(
                share_reserves,
                share_adjustment,
                bond_reserves,
                minimum_share_reserves,
                share_reserves_delta,
            )
            .unwrap();

        // Update and return the new state.
        let mut new_info = self.info.clone();
        new_info.share_reserves = U256::from(updated_share_reserves);
        new_info.share_adjustment = updated_share_adjustment;
        new_info.bond_reserves = U256::from(updated_bond_reserves);
        State {
            config: self.config.clone(),
            info: new_info,
        }
    }

    fn calculate_update_liquidity(
        &self,
        share_reserves: FixedPoint,
        share_adjustment: I256,
        bond_reserves: FixedPoint,
        minimum_share_reserves: FixedPoint,
        share_reserves_delta: I256,
    ) -> Result<(FixedPoint, I256, FixedPoint), &'static str> {
        if share_reserves_delta == I256::zero() {
            return Ok((share_reserves, share_adjustment, bond_reserves));
        }

        // Get the updated share reserves.
        let new_share_reserves = if share_reserves_delta > I256::zero() {
            share_reserves + FixedPoint::from(share_reserves_delta)
        } else {
            share_reserves - FixedPoint::from(share_reserves_delta)
        };

        // Ensure the minimum share reserve level.
        if new_share_reserves < minimum_share_reserves {
            return Err("Update would result in share reserves below minimum.");
        }

        // Get the updated share adjustment.
        let new_share_adjustment = if share_adjustment >= I256::zero() {
            let share_adjustment_fp = FixedPoint::from(share_adjustment);
            I256::try_from(new_share_reserves.mul_div_down(share_adjustment_fp, share_reserves))
                .unwrap()
        } else {
            let share_adjustment_fp = FixedPoint::from(-share_adjustment);
            -I256::try_from(new_share_reserves.mul_div_up(share_adjustment_fp, share_reserves))
                .unwrap()
        };

        // Get the updated bond reserves.
        let old_effective_share_reserves =
            get_effective_share_reserves(self.effective_share_reserves(), self.share_adjustment());
        let new_effective_share_reserves =
            get_effective_share_reserves(new_share_reserves, new_share_adjustment);
        let new_bond_reserves =
            bond_reserves.mul_div_down(new_effective_share_reserves, old_effective_share_reserves);

        Ok((new_share_reserves, new_share_adjustment, new_bond_reserves))
    }
}

#[cfg(test)]
mod tests {
    use std::panic;

    use eyre::Result;
    use hyperdrive_wrappers::wrappers::mock_lp_math::PresentValueParams;
    use rand::{thread_rng, Rng};
    use test_utils::{chain::TestChainWithMocks, constants::FAST_FUZZ_RUNS};

    use super::*;

    #[tokio::test]
    async fn fuzz_calculate_present_value() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_lp_math();

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
                    vault_share_price: state.info.vault_share_price,
                    initial_vault_share_price: state.config.initial_vault_share_price,
                    minimum_share_reserves: state.config.minimum_share_reserves,
                    minimum_transaction_amount: state.config.minimum_transaction_amount,
                    long_average_time_remaining: state
                        .calculate_normalized_time_remaining(
                            state.long_average_maturity_time().into(),
                            current_block_timestamp.into(),
                        )
                        .into(),
                    short_average_time_remaining: state
                        .calculate_normalized_time_remaining(
                            state.short_average_maturity_time().into(),
                            current_block_timestamp.into(),
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
        let mock = chain.mock_lp_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let current_block_timestamp = rng.gen_range(fixed!(1)..=fixed!(1e4));
            let long_average_time_remaining = state.calculate_normalized_time_remaining(
                state.long_average_maturity_time().into(),
                current_block_timestamp.into(),
            );
            let short_average_time_remaining = state.calculate_normalized_time_remaining(
                state.short_average_maturity_time().into(),
                current_block_timestamp.into(),
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
                    vault_share_price: state.info.vault_share_price,
                    initial_vault_share_price: state.config.initial_vault_share_price,
                    minimum_share_reserves: state.config.minimum_share_reserves,
                    minimum_transaction_amount: state.config.minimum_transaction_amount,
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
        let mock = chain.mock_lp_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let current_block_timestamp = rng.gen_range(fixed!(1)..=fixed!(1e4));
            let long_average_time_remaining = state.calculate_normalized_time_remaining(
                state.long_average_maturity_time().into(),
                current_block_timestamp.into(),
            );
            let short_average_time_remaining = state.calculate_normalized_time_remaining(
                state.short_average_maturity_time().into(),
                current_block_timestamp.into(),
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
                    vault_share_price: state.info.vault_share_price,
                    initial_vault_share_price: state.config.initial_vault_share_price,
                    minimum_share_reserves: state.config.minimum_share_reserves,
                    minimum_transaction_amount: state.config.minimum_transaction_amount,
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
