use std::{convert::TryFrom, error::Error, fmt};

use ethers::types::{I256, U256};
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

use crate::{State, YieldSpace};

impl State {
    fn calculate_fees_given_bonds(
        &self,
        bond_amount: FixedPoint,
        normalized_time_remaining: FixedPoint,
        spot_price: FixedPoint,
        vault_share_price: FixedPoint,
    ) -> (FixedPoint, FixedPoint, FixedPoint, FixedPoint) {
        // NOTE: Round up to overestimate the curve fee.
        //
        // p (spot price) tells us how many base a bond is worth -> p = base/bonds
        // 1 - p tells us how many additional base a bond is worth at
        // maturity -> (1 - p) = additional base/bonds
        //
        // The curve fee is taken from the additional base the user gets for
        // each bond at maturity:
        //
        // curve fee = ((1 - p) * phi_curve * d_y * t)/c
        //           = (base/bonds * phi_curve * bonds * t) / (base/shares)
        //           = (base/bonds * phi_curve * bonds * t) * (shares/base)
        //           = (base * phi_curve * t) * (shares/base)
        //           = phi_curve * t * shares
        let curve_fee = self
            .curve_fee()
            .mul_up(fixed!(1e18) - self.get_spot_price())
            .mul_up(bond_amount)
            .mul_div_up(normalized_time_remaining, vault_share_price);

        // NOTE: Round down to underestimate the governance curve fee.
        //
        // Calculate the curve portion of the governance fee:
        //
        // governanceCurveFee = curve_fee * phi_gov
        //                    = shares * phi_gov

        let governance_curve_fee = curve_fee * self.governance_lp_fee();

        // NOTE: Round up to overestimate the flat fee.
        //
        // The flat portion of the fee is taken from the matured bonds.
        // Since a matured bond is worth 1 base, it is appropriate to consider
        // d_y in units of base:
        //
        // flat fee = (d_y * (1 - t) * phi_flat) / c
        //          = (base * (1 - t) * phi_flat) / (base/shares)
        //          = (base * (1 - t) * phi_flat) * (shares/base)
        //          = shares * (1 - t) * phi_flat
        let flat =
            bond_amount.mul_div_up(fixed!(1e18) - normalized_time_remaining, vault_share_price);

        let flat_fee = flat.mul_up(self.flat_fee());

        // NOTE: Round down to underestimate the total governance fee.
        //
        // We calculate the flat portion of the governance fee as:
        //
        // governance_flat_fee = flat_fee * phi_gov
        //                     = shares * phi_gov
        //
        // The totalGovernanceFee is the sum of the curve and flat governance fees.
        let total_governance_fee =
            governance_curve_fee + flat_fee.mul_down(self.governance_lp_fee());

        return (
            curve_fee,
            flat_fee,
            governance_curve_fee,
            total_governance_fee,
        );
    }

    fn calculate_close_short_curve<F: Into<FixedPoint>>(
        &self,
        bond_amount: F,
        normalized_time_remaining: F,
    ) -> FixedPoint {
        let bond_amount = bond_amount.into();
        let normalized_time_remaining = normalized_time_remaining.into();

        // NOTE: We overestimate the trader's share payment to avoid sandwiches.
        //
        // Calculate the curve part of the trade
        let curve = if normalized_time_remaining > fixed!(0) {
            // NOTE: Round the `shareCurveDelta` up to overestimate the share
            // payment.
            //
            let curve_bonds_in = bond_amount * normalized_time_remaining;
            self.calculate_shares_in_given_bonds_out_up_safe(curve_bonds_in)
                .unwrap()
        } else {
            fixed!(0)
        };

        curve
    }

    fn calculate_close_short_flat_plus_curve<F: Into<FixedPoint>>(
        &self,
        bond_amount: F,
        normalized_time_remaining: F,
    ) -> FixedPoint {
        let bond_amount = bond_amount.into();
        let normalized_time_remaining = normalized_time_remaining.into();

        // NOTE: We overestimate the trader's share payment to avoid sandwiches.
        //
        // Calculate the flat part of the trade
        let flat = bond_amount.mul_div_up(
            fixed!(1e18) - normalized_time_remaining,
            self.vault_share_price(),
        );

        // Calculate the curve part of the trade
        let curve = self.calculate_close_short_curve(bond_amount, normalized_time_remaining);

        flat + curve
    }

    // Calculates the proceeds in shares of closing a short position.
    fn calculate_short_proceeds(
        &self,
        bond_amount: FixedPoint,
        share_amount: FixedPoint,
        open_vault_share_price: FixedPoint,
        close_vault_share_price: FixedPoint,
        vault_share_price: FixedPoint,
        flat_fee: FixedPoint,
    ) -> FixedPoint {
        let mut bond_factor = bond_amount
            .mul_div_down(
                close_vault_share_price,
                // We round up here do avoid overestimating the share proceeds.
                open_vault_share_price,
            )
            .div_down(vault_share_price);
        bond_factor += bond_amount.mul_div_down(flat_fee, vault_share_price);

        if bond_factor > share_amount {
            // proceeds = (c1 / c0 * c) * dy - dz
            bond_factor - share_amount
        } else {
            fixed!(0)
        }
    }

    /// Gets the amount of shares the trader will receive after fees for closing a short
    pub fn calculate_close_short<F: Into<FixedPoint>>(
        &self,
        bond_amount: F,
        open_vault_share_price: F,
        close_vault_share_price: F,
        normalized_time_remaining: F,
    ) -> FixedPoint {
        let bond_amount = bond_amount.into();
        let open_vault_share_price = open_vault_share_price.into();
        let close_vault_share_price = close_vault_share_price.into();
        let normalized_time_remaining = normalized_time_remaining.into();

        // Calculate flat + curve for the short.
        let share_reserves_delta =
            self.calculate_close_short_flat_plus_curve(bond_amount, normalized_time_remaining);
        // let bond_reserves_delta = bond_amount.mul_up(normalized_time_remaining);

        // Throw an error if closing the short would result in negative interest.
        let bond_delta = bond_amount * normalized_time_remaining;
        let ending_spot_price = self.spot_price_after_close_short(share_reserves_delta, bond_delta);
        let max_spot_price = self.calculate_close_short_max_spot_price();
        println!("\n  calculate_close_short");
        println!("ending_spot_price           {:#?}", ending_spot_price);
        println!("max_spot_price              {:#?}", max_spot_price);
        // TODO: if we support negative interest we'll need to remove this panic and support that path.
        if ending_spot_price > max_spot_price {
            // TODO would be nice to return a `Result` here instead of a panic.
            panic!("InsufficientLiquidity: Negative Interest");
        }

        // Subtract the fees from the trade.
        // let share_reserves_delta_with_fees = share_reserves_delta
        //     + self.close_short_curve_fee(bond_amount, normalized_time_remaining)
        //     + self.close_short_flat_fee(bond_amount, normalized_time_remaining);

        // Calculate the share proceeds owed to the short.
        // let short_proceeds = self.calculate_short_proceeds(
        //     bond_amount,
        //     share_reserves_delta_with_fees,
        //     open_vault_share_price,
        //     close_vault_share_price,
        //     self.vault_share_price(),
        //     self.flat_fee(),
        // );

        // let (curve_fee, flat_fee, governance_curve_fee, total_governance_fee) = self
        let (curve_fee, flat_fee, _, _) = self.calculate_fees_given_bonds(
            bond_amount,
            normalized_time_remaining,
            self.get_spot_price(),
            self.vault_share_price(),
        );

        // let share_curve_delta =
        //     self.calculate_close_short_curve(bond_amount, normalized_time_remaining);
        // let share_curve_delta = share_curve_delta + curve_fee - governance_curve_fee;
        let share_reserves_delta = share_reserves_delta + curve_fee + flat_fee;

        let short_proceeds = self.calculate_short_proceeds(
            bond_amount,
            share_reserves_delta,
            open_vault_share_price,
            close_vault_share_price,
            self.vault_share_price(),
            self.flat_fee(),
        );

        // // The governance fee isn't included in the share payment that is
        // // added to the share reserves. We remove it here to simplify the
        // // accounting updates.
        // shareReservesDelta -= totalGovernanceFee;
        // let share_reserves_delta = share_reserves_delta - total_governance_fee;

        // // Ensure that the ending spot price is less than 1.
        // if (
        //     HyperdriveMath.calculateSpotPrice(
        //         _effectiveShareReserves() + shareCurveDelta,
        //         _marketState.bondReserves - bondReservesDelta,
        //         _initialVaultSharePrice,
        //         _timeStretch
        //     ) > ONE
        // ) {
        //     Errors.throwInsufficientLiquidityError(
        //         IHyperdrive.InsufficientLiquidityReason.NegativeInterest
        //     );
        // }
        // let spot_price = self.spot_price_after_close_short(share_curve_delta, bond_reserves_delta);

        return short_proceeds;
    }

    /// Gets the spot price after closing a short.
    pub fn calculate_spot_price_after_close_short<F: Into<FixedPoint>>(
        &self,
        bond_amount: F,
        normalized_time_remaining: F,
    ) -> FixedPoint {
        // Calculate share and bond deltas from flat + curve.
        let bond_amount = bond_amount.into();
        let normalized_time_remaining = normalized_time_remaining.into();
        let share_delta =
            self.calculate_close_short_flat_plus_curve(bond_amount, normalized_time_remaining);
        let bond_delta = bond_amount * normalized_time_remaining;

        // Apply the deltas and return the new spot price.
        self.spot_price_after_close_short(share_delta, bond_delta)
    }

    // Applies share and bond deltas to the pool's reserves as if a user closed a short and returns
    // the spot price.
    fn spot_price_after_close_short(
        &self,
        share_amount: FixedPoint,
        bond_amount: FixedPoint,
    ) -> FixedPoint {
        let mut state: State = self.clone();
        state.info.bond_reserves -= bond_amount.into();
        state.info.share_reserves += share_amount.into();
        state.get_spot_price()
    }
}

#[cfg(test)]
mod tests {
    use std::panic;

    use ethers::{
        abi::Detokenize,
        contract::ContractCall,
        prelude::EthLogDecode,
        providers::{Http, Middleware, Provider, RetryClient},
        types::{Address, BlockId, I256, U256},
    };
    use eyre::Result;
    use hyperdrive_wrappers::wrappers::{
        erc4626_hyperdrive::ERC4626Hyperdrive,
        mock_erc4626::MockERC4626,
        mock_hyperdrive::{MarketState, MockHyperdrive},
    };
    use rand::{thread_rng, Rng};
    use test_utils::{
        chain::{Chain, TestChainWithMocks},
        constants::FAST_FUZZ_RUNS,
    };

    use super::*;
    use crate::State;

    #[tokio::test]
    async fn fuzz_calculate_short_proceeds() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_hyperdrive_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let bond_amount = rng.gen_range(fixed!(0)..=state.bond_reserves());
            let share_amount = rng.gen_range(fixed!(0)..=bond_amount);
            let open_vault_share_price = rng.gen_range(fixed!(0)..=state.vault_share_price());
            let actual = panic::catch_unwind(|| {
                state.calculate_short_proceeds(
                    bond_amount,
                    share_amount,
                    open_vault_share_price,
                    state.vault_share_price(),
                    state.vault_share_price(),
                    state.flat_fee(),
                )
            });
            match mock
                .calculate_short_proceeds_down(
                    bond_amount.into(),
                    share_amount.into(),
                    open_vault_share_price.into(),
                    state.vault_share_price().into(),
                    state.vault_share_price().into(),
                    state.flat_fee().into(),
                )
                .call()
                .await
            {
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected)),
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_calculate_close_short_flat_plus_curve() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_hyperdrive_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let in_ = rng.gen_range(fixed!(0)..=state.bond_reserves());
            let normalized_time_remaining = rng.gen_range(fixed!(0)..=fixed!(1e18));
            let actual = panic::catch_unwind(|| {
                state.calculate_close_short_flat_plus_curve(in_, normalized_time_remaining)
            });
            match mock
                .calculate_close_short(
                    state.effective_share_reserves().into(),
                    state.bond_reserves().into(),
                    in_.into(),
                    normalized_time_remaining.into(),
                    state.t().into(),
                    state.c().into(),
                    state.mu().into(),
                )
                .call()
                .await
            {
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected.2)),
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_calculate_close_short_with_fees() -> Result<()> {
        let mut rng = thread_rng();
        let chain = TestChainWithMocks::new(1).await?;

        // Fuzz the rust and solidity implementations against each other.
        for _ in 0..*FAST_FUZZ_RUNS {
            // Deploy the mock with a fresh, randomized state.
            let state = rng.gen::<State>();
            let client = chain
                .chain()
                .client(chain.chain().accounts()[0].clone())
                .await?;
            let mock = MockHyperdrive::deploy(client.clone(), (state.clone().config,))?
                .send()
                .await?;

            // Figure out the maturity time.
            let timestamp = client
                .get_block(client.get_block_number().await.unwrap())
                .await?
                .unwrap()
                .timestamp;
            let checkpoint_duration = U256::from(state.checkpoint_duration());
            let time_lapsed_in_seconds =
                U256::from(rng.gen_range(fixed!(0)..=state.position_duration()));
            let maturity_time =
                (time_lapsed_in_seconds + timestamp) / checkpoint_duration * checkpoint_duration;
            let latest_checkpoint_time =
                (time_lapsed_in_seconds + timestamp) / checkpoint_duration * checkpoint_duration;

            // Set the starting_vault_share_price for the mock.
            let starting_time = maturity_time - U256::from(state.position_duration());
            let starting_vault_share_price = rng.gen_range(fixed!(0.5e18)..=fixed!(2.5e18));

            let remainder = starting_time % checkpoint_duration;
            println!("remainder {:#?}", remainder);

            let checkpoint_duration = mock.get_checkpoint_duration().call().await?;
            let remainder = starting_time % checkpoint_duration;
            println!("remainder {:#?}", remainder);

            // Set the opening checkpoint's vault share price.
            let _ = mock
                .set_checkpoint(starting_time, U256::from(starting_vault_share_price))
                .send()
                .await?;

            // Get the normalized time remaining for the short.
            let normalized_time_remaining =
                mock.calculate_time_remaining(maturity_time).call().await?;

            // Generate random variables to close the short with.
            let in_ = rng.gen_range(fixed!(0)..=state.bond_reserves());
            let close_vault_share_price = rng.gen_range(fixed!(5e17)..=fixed!(10e18));

            // Check a bunch of stuff
            let _ = mock.get_mock_checkpoint(starting_time).call().await?;
            let _ = mock.get_mock_checkpoint(starting_time).call().await?;
            let _ = mock.get_mock_checkpoint(starting_time).call().await?;
            let _ = mock.get_mock_checkpoint(starting_time).call().await?;
            let mock_checkpoint_value = mock.get_mock_checkpoint(starting_time).call().await?;
            println!("start_time                  {:#?}", starting_time);
            println!("timestamp                   {:#?}", timestamp);
            println!("maturity_time               {:#?}", maturity_time);
            println!(
                "starting_vault_share_price  {:#?}",
                starting_vault_share_price
            );
            println!("mock_checkpoint_value       {:#?}", mock_checkpoint_value);
            println!(
                "mock_checkpoint_value       {:#?}",
                FixedPoint::from(mock_checkpoint_value)
            );
            println!(
                " normalized_time_remaining  {:#?}",
                FixedPoint::from(normalized_time_remaining)
            );
            println!("close_vault_share_price     {:#?}", close_vault_share_price);

            // sanity check to make sure we aren't failing because of a conversion since
            // share_adjustment in PoolInfo is a I256 and an i128 in MarketState.
            assert!(state.share_adjustment() <= i128::MAX.into());

            // Get the result of the rust function.
            let rust_result = panic::catch_unwind(|| {
                state.calculate_close_short(
                    in_,
                    state.initial_vault_share_price(),
                    close_vault_share_price,
                    FixedPoint::from(normalized_time_remaining),
                )
            });

            // Get the result of the solidity function.
            let mock_result = mock
                .calculate_close_short(in_.into(), close_vault_share_price.into(), maturity_time)
                .call()
                .await;

            // TODO: change this to match mock {...} once mock_result actually returns values.
            // Compare the result with the expected output to validate the correctness of the
            // implementation.
            match rust_result {
                Ok(rust_share_proceeds) => {
                    println!("result      {:#?} ", rust_result);
                    println!("mock_result {:#?}", mock_result);
                    let solidity_share_proceeds = FixedPoint::from(mock_result.unwrap().1);
                    assert_eq!(rust_share_proceeds, solidity_share_proceeds);
                }
                Err(err) => {
                    println!("error {:#?}", err);
                    // assert!(result.is_err());
                    assert!(mock_result.is_err());
                }
            }
            println!("");
        }
        Ok(())
    }
}
