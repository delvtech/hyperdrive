use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

use crate::{State, YieldSpace};

impl State {
    fn calculate_close_long_flat_plus_curve<F: Into<FixedPoint>>(
        &self,
        bond_amount: F,
        normalized_time_remaining: F,
    ) -> FixedPoint {
        let bond_amount = bond_amount.into();
        let normalized_time_remaining = normalized_time_remaining.into();

        // Calculate the flat part of the trade
        let flat = bond_amount.mul_div_down(
            fixed!(1e18) - normalized_time_remaining,
            self.vault_share_price(),
        );

        // Calculate the curve part of the trade
        let curve = if normalized_time_remaining > fixed!(0) {
            let curve_bonds_in = bond_amount * normalized_time_remaining;
            self.calculate_shares_out_given_bonds_in_down(curve_bonds_in)
        } else {
            fixed!(0)
        };

        flat + curve
    }

    /// Gets the amount of shares the trader will receive after fees for closing a long
    pub fn calculate_close_long<F: Into<FixedPoint>>(
        &self,
        bond_amount: F,
        normalized_time_remaining: F,
    ) -> FixedPoint {
        let bond_amount = bond_amount.into();
        let normalized_time_remaining = normalized_time_remaining.into();

        // Subtract the fees from the trade
        self.calculate_close_long_flat_plus_curve(bond_amount, normalized_time_remaining)
            - self.close_long_curve_fee(bond_amount, normalized_time_remaining)
            - self.close_long_flat_fee(bond_amount, normalized_time_remaining)
    }
}

#[cfg(test)]
mod tests {
    use std::panic;

    use ethers::signers::{LocalWallet, Signer};
    use eyre::Result;
    use fixed_point_macros::uint256;
    use hyperdrive_wrappers::wrappers::mock_hyperdrive_math::MockHyperdriveMath;
    use rand::{thread_rng, Rng};
    use test_utils::{
        chain::{Chain, ChainClient},
        constants::{ALICE, FAST_FUZZ_RUNS},
    };

    use super::*;
    use crate::State;

    async fn setup() -> Result<MockHyperdriveMath<ChainClient<LocalWallet>>> {
        let chain = Chain::connect(None).await?;
        chain.deal(ALICE.address(), uint256!(100_000e18)).await?;
        let mock = MockHyperdriveMath::deploy(chain.client(ALICE.clone()).await?, ())?
            .send()
            .await?;
        Ok(mock)
    }

    #[tokio::test]
    async fn fuzz_calculate_close_long_flat_plus_curve() -> Result<()> {
        let mock = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let in_ = rng.gen_range(fixed!(0)..=state.effective_share_reserves());
            let normalized_time_remaining = rng.gen_range(fixed!(0)..=fixed!(1e18));
            let actual = panic::catch_unwind(|| {
                state.calculate_close_long_flat_plus_curve(in_, normalized_time_remaining)
            });
            match mock
                .calculate_close_long(
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
}
