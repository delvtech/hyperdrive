use ethers::types::{I256, U256};
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, uint256};

pub fn calculate_time_stretch(rate: FixedPoint, position_duration: FixedPoint) -> FixedPoint {
    let seconds_in_a_year = FixedPoint::from(U256::from(60 * 60 * 24 * 365));
    // Calculate the benchmark time stretch. This time stretch is tuned for
    // a position duration of 1 year.
    let time_stretch = fixed!(5.24592e18)
        / (fixed!(0.04665e18) * FixedPoint::from(U256::from(rate) * uint256!(100)));
    let time_stretch = fixed!(1e18) / time_stretch;

    // We know that the following simultaneous equations hold:
    //
    // (1 + apr) * A ** timeStretch = 1
    //
    // and
    //
    // (1 + apr * (positionDuration / 365 days)) * A ** targetTimeStretch = 1
    //
    // where A is the reserve ratio. We can solve these equations for the
    // target time stretch as follows:
    //
    // targetTimeStretch = (
    //     ln(1 + apr * (positionDuration / 365 days)) /
    //     ln(1 + apr)
    // ) * timeStretch
    //
    // NOTE: Round down so that the output is an underestimate.
    (FixedPoint::from(FixedPoint::ln(
        I256::try_from(fixed!(1e18) + rate.mul_div_down(position_duration, seconds_in_a_year))
            .unwrap(),
    )) / FixedPoint::from(FixedPoint::ln(I256::try_from(fixed!(1e18) + rate).unwrap())))
        * time_stretch
}

pub fn calculate_effective_share_reserves(
    share_reserves: FixedPoint,
    share_adjustment: I256,
) -> FixedPoint {
    let effective_share_reserves = I256::try_from(share_reserves).unwrap() - share_adjustment;
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
    // NOTE: Round down to underestimate the initial bond reserves.
    //
    // Normalize the time to maturity to fractions of a year since the provided
    // rate is an APR.
    let t = position_duration / FixedPoint::from(U256::from(60 * 60 * 24 * 365));

    // NOTE: Round down to underestimate the initial bond reserves.
    //
    // inner = (1 + apr * t) ** (1 / t_s)
    let mut inner = fixed!(1e18) + apr.mul_down(t);
    if inner >= fixed!(1e18) {
        // Rounding down the exponent results in a smaller result.
        inner = inner.pow(fixed!(1e18) / time_stretch);
    } else {
        // Rounding up the exponent results in a smaller result.
        inner = inner.pow(fixed!(1e18).div_up(time_stretch));
    }

    // NOTE: Round down to underestimate the initial bond reserves.
    //
    // mu * (z - zeta) * (1 + apr * t) ** (1 / tau)
    initial_vault_share_price
        .mul_down(effective_share_reserves)
        .mul_down(inner)
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
    async fn fuzz_calculate_time_stretch() -> Result<()> {
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
            let actual_t = calculate_time_stretch(apr, position_duration);
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
            let effective_share_reserves = calculate_effective_share_reserves(
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
