use ethers::types::{I256, U256};
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, uint256};

pub fn get_time_stretch(rate: FixedPoint, position_duration: FixedPoint) -> FixedPoint {
    let seconds_in_a_year = FixedPoint::from(U256::from(60 * 60 * 24 * 365));
    // Calculate the benchmark time stretch. This time stretch is tuned for
    // a position duration of 1 year.
    let time_stretch = fixed!(5.24592e18)
        / (fixed!(0.04665e18) * FixedPoint::from(U256::from(rate) * uint256!(100)));
    let time_stretch = fixed!(1e18) / time_stretch;
    // if the position duration is 1 year, we can return the benchmark
    if position_duration == seconds_in_a_year {
        return time_stretch;
    }

    // Otherwise, we need to adjust the time stretch to account for the
    // position duration. We do this by holding the reserve ratio constant
    // and solving for the new time stretch directly.
    //
    // We can calculate the spot price at the target apr and position
    // duration as:
    //
    // p = 1 / (1 + apr * (positionDuration / 365 days))
    //
    // We then calculate the benchmark reserve ratio, `ratio`, implied by
    // the benchmark time stretch using the `calculateInitialBondReserves`
    // function.
    //
    // We can then derive the adjusted time stretch using the spot price
    // calculation:
    //
    // p = ratio ** timeStretch
    //          =>
    // timeStretch = ln(p) / ln(ratio)
    let target_spot_price =
        fixed!(1e18) / (fixed!(1e18) + rate.mul_div_down(position_duration, seconds_in_a_year));
    let benchmark_reserve_ratio = fixed!(1e18)
        / calculate_initial_bond_reserves(
            fixed!(1e18),
            fixed!(1e18),
            rate,
            seconds_in_a_year,
            time_stretch,
        );
    // target spot price and benchmark reserve ratio will have negative ln,
    // but since we are dividing them we can cast to positive before converting types
    // TODO: implement FixedPoint `neg` pub fn to support "-"
    let new_time_stretch = FixedPoint::from(-FixedPoint::ln(I256::from(target_spot_price)))
        / FixedPoint::from(-FixedPoint::ln(I256::from(benchmark_reserve_ratio)));
    new_time_stretch
}

pub fn get_effective_share_reserves(
    share_reserves: FixedPoint,
    share_adjustment: I256,
) -> FixedPoint {
    let effective_share_reserves = I256::from(share_reserves) - share_adjustment;
    if effective_share_reserves < I256::from(0) {
        panic!("effective share reserves cannot be negative");
    }
    effective_share_reserves.into()
}

/// Calculates the bond reserves assuming that the pool has a given
/// share reserves and fixed rate APR.
///
/// r = ((1 / p) - 1) / t = (1 - p) / (pt)
/// p = ((u * z) / y) ** t
///
/// Arguments:
///
/// * effective_share_reserves : The pool's effective share reserves. The
/// effective share reserves are a modified version of the share
/// reserves used when pricing trades.
/// * initial_vault_share_price : The pool's initial vault share price.
/// * apr : The pool's APR.
/// * position_duration : The amount of time until maturity in seconds.
/// * time_stretch : The time stretch parameter.
///
/// Returns:
///
/// * bond_reserves : The bond reserves (without adjustment) that make
/// the pool have a specified APR.
pub fn calculate_initial_bond_reserves(
    effective_share_reserves: FixedPoint,
    initial_vault_share_price: FixedPoint,
    apr: FixedPoint,
    position_duration: FixedPoint,
    time_stretch: FixedPoint,
) -> FixedPoint {
    let annualized_time = position_duration / FixedPoint::from(U256::from(60 * 60 * 24 * 365));
    // mu * (z - zeta) * (1 + apr * t) ** (1 / tau)
    initial_vault_share_price
        .mul_down(effective_share_reserves)
        .mul_down(
            (fixed!(1e18) + apr.mul_down(annualized_time)).pow(fixed!(1e18).div_up(time_stretch)),
        )
}

#[cfg(test)]
mod tests {
    use std::panic;

    use eyre::Result;
    use rand::{thread_rng, Rng};
    use test_utils::{chain::TestChainWithMocks, constants::FAST_FUZZ_RUNS};

    use super::*;
    use crate::State;

    #[tokio::test]
    async fn fuzz_get_time_stretch() -> Result<()> {
        // Spin up a fake chain & deploy mock hyperdrive math.
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_hyperdrive_math();
        // Fuzz the rust and solidity implementations against each other.
        let seconds_in_ten_years = U256::from(10 * 60 * 60 * 24 * 365);
        let seconds_in_a_day = U256::from(60 * 60 * 24);
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            // Get the current state of the mock contract
            let position_duration = rng.gen_range(
                FixedPoint::from(seconds_in_a_day)..=FixedPoint::from(seconds_in_ten_years),
            );
            let apr = rng.gen_range(fixed!(0.001e18)..=fixed!(10.0e18));
            let actual_t = get_time_stretch(apr, position_duration);
            match mock
                .calculate_time_stretch(apr.into(), position_duration.into())
                .call()
                .await
            {
                Ok(expected_t) => {
                    assert_eq!(actual_t, FixedPoint::from(expected_t));
                }
                Err(_) => panic!("Test failed."),
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_calculate_initial_bond_reserves() -> Result<()> {
        // Spin up a fake chain & deploy mock hyperdrive math.
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_hyperdrive_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            // Get the current state of the mock contract
            let state = rng.gen::<State>();
            let effective_share_reserves = get_effective_share_reserves(
                state.info.share_reserves.into(),
                state.info.share_adjustment.into(),
            );
            // Calculate the bonds
            let actual = calculate_initial_bond_reserves(
                effective_share_reserves,
                state.config.initial_vault_share_price.into(),
                fixed!(0.01e18),
                state.config.position_duration.into(),
                state.config.time_stretch.into(),
            );
            match mock
                .calculate_initial_bond_reserves(
                    effective_share_reserves.into(),
                    state.config.initial_vault_share_price,
                    fixed!(0.01e18).into(),
                    state.config.position_duration,
                    state.config.time_stretch,
                )
                .call()
                .await
            {
                Ok(expected_y) => {
                    assert_eq!(actual, FixedPoint::from(expected_y));
                }
                Err(_) => panic!("Test failed."),
            }
        }

        Ok(())
    }
}
