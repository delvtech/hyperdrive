use eyre::{eyre, Result};
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

pub trait YieldSpace {
    /// Info ///

    fn z(&self) -> FixedPoint;

    fn y(&self) -> FixedPoint;

    fn c(&self) -> FixedPoint;

    fn mu(&self) -> FixedPoint;

    fn t(&self) -> FixedPoint;

    /// Core ///

    fn get_spot_price(&self) -> FixedPoint {
        ((self.mu() * self.z()) / self.y()).pow(self.t())
    }

    /// Calculates the amount of bonds a user will receive from the pool by
    /// providing a specified amount of shares. We underestimate the amount of
    /// bonds out to prevent sandwiches.
    fn calculate_bonds_out_given_shares_in_down(&self, dz: FixedPoint) -> FixedPoint {
        // NOTE: We round k up to make the rhs of the equation larger.
        //
        // k = (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
        let k = self.k_up();

        // NOTE: We round z down to make the rhs of the equation larger.
        //
        // (µ * (z + dz))^(1 - t)
        let mut z = (self.mu() * (self.z() + dz)).pow(fixed!(1e18) - self.t());
        // (c / µ) * (µ * (z + dz))^(1 - t)
        z = self.c().mul_div_down(z, self.mu());

        // NOTE: We round _y up to make the rhs of the equation larger.
        //
        // k - (c / µ) * (µ * (z + dz))^(1 - t))^(1 / (1 - t)))
        let mut y = k - z;
        if y >= fixed!(1e18) {
            // Rounding up the exponent results in a larger result.
            y = y.pow(fixed!(1e18).div_up(fixed!(1e18) - self.t()));
        } else {
            // Rounding down the exponent results in a larger result.
            y = y.pow(fixed!(1e18) / (fixed!(1e18) - self.t()));
        }

        // Δy = y - (k - (c / µ) * (µ * (z + dz))^(1 - t))^(1 / (1 - t)))
        self.y() - y
    }

    /// Calculates the amount of shares a user must provide the pool to receive
    /// a specified amount of bonds. We overestimate the amount of shares in.
    fn calculate_shares_in_given_bonds_out_up(&self, dy: FixedPoint) -> FixedPoint {
        // NOTE: We round k up to make the lhs of the equation larger.
        //
        // k = (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
        let k = self.k_up();

        // (y - dy)^(1 - t)
        let y = (self.y() - dy).pow(fixed!(1e18) - self.t());

        // NOTE: We round _z up to make the lhs of the equation larger.
        //
        // ((k - (y - dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))
        let mut z = (k - y).mul_div_up(self.mu(), self.c());
        if z >= fixed!(1e18) {
            // Rounding up the exponent results in a larger result.
            z = z.pow(fixed!(1e18).div_up(fixed!(1e18) - self.t()));
        } else {
            // Rounding down the exponent results in a larger result.
            z = z.pow(fixed!(1e18) / (fixed!(1e18) - self.t()));
        }
        // ((k - (y - dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))) / µ
        z = z.div_up(self.mu());

        // Δz = (((k - (y - dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))) / µ - z
        z - self.z()
    }

    /// Calculates the amount of shares a user must provide the pool to receive
    /// a specified amount of bonds. We underestimate the amount of shares in.
    fn calculate_shares_in_given_bonds_out_down(&self, dy: FixedPoint) -> FixedPoint {
        // NOTE: We round k down to make the lhs of the equation smaller.
        //
        // k = (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
        let k = self.k_down();

        // (y - dy)^(1 - t)
        let y = (self.y() - dy).pow(fixed!(1e18) - self.t());

        // NOTE: We round _z down to make the lhs of the equation smaller.
        //
        // ((k - (y - dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))
        let mut z = (k - y).mul_div_down(self.mu(), self.c());
        if z >= fixed!(1e18) {
            // Rounding down the exponent results in a smaller result.
            z = z.pow(fixed!(1e18) / (fixed!(1e18) - self.t()));
        } else {
            // Rounding up the exponent results in a smaller result.
            z = z.pow(fixed!(1e18).div_up(fixed!(1e18) - self.t()));
        }
        // ((k - (y - dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))) / µ
        z /= self.mu();

        // Δz = (((k - (y - dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))) / µ - z
        z - self.z()
    }

    /// Calculates the amount of shares a user will receive from the pool by
    /// providing a specified amount of bonds. This function reverts if an
    /// integer overflow or underflow occurs. We underestimate the amount of
    /// shares out.
    fn calculate_shares_out_given_bonds_in_down(&self, dy: FixedPoint) -> FixedPoint {
        self.calculate_shares_out_given_bonds_in_down_safe(dy)
            .unwrap()
    }

    /// Calculates the amount of shares a user will receive from the pool by
    /// providing a specified amount of bonds. This function returns a Result
    /// instead of panicking. We underestimate the amount of shares out.
    fn calculate_shares_out_given_bonds_in_down_safe(&self, dy: FixedPoint) -> Result<FixedPoint> {
        // NOTE: We round k up to make the rhs of the equation larger.
        //
        // k = (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
        let k = self.k_up();

        // (y + dy)^(1 - t)
        let y = (self.y() + dy).pow(fixed!(1e18) - self.t());

        // If k is less than y, we return with a failure flag.
        if k < y {
            return Err(eyre!(
                "calculate_shares_out_given_bonds_in_down_safe: k = {} < {} = y",
                k,
                y
            ));
        }

        // NOTE: We round _z up to make the rhs of the equation larger.
        //
        // ((k - (y + dy)^(1 - t)) / (c / µ))^(1 / (1 - t)))
        let mut z = (k - y).mul_div_up(self.mu(), self.c());
        if z >= fixed!(1e18) {
            // Rounding the exponent up results in a larger outcome.
            z = z.pow(fixed!(1e18).div_up(fixed!(1e18) - self.t()));
        } else {
            // Rounding the exponent down results in a larger outcome.
            z = z.pow(fixed!(1e18) / (fixed!(1e18) - self.t()));
        }
        // ((k - (y + dy)^(1 - t) ) / (c / µ))^(1 / (1 - t))) / µ
        z = z.div_up(self.mu());

        // Δz = z - ((k - (y + dy)^(1 - t) ) / (c / µ))^(1 / (1 - t)) / µ
        if self.z() > z {
            Ok(self.z() - z)
        } else {
            Ok(fixed!(0))
        }
    }

    /// Calculates the maximum amount of bonds that can be purchased with the
    /// specified reserves. We round so that the max buy amount is
    /// underestimated.
    fn calculate_max_buy(&self) -> FixedPoint {
        // We solve for the maximum buy using the constraint that the pool's
        // spot price can never exceed 1. We do this by noting that a spot price
        // of 1, (mu * z) / y ** tau = 1, implies that mu * z = y. This
        // simplifies YieldSpace to k = ((c / mu) + 1) * y' ** (1 - tau), and
        // gives us the maximum bond reserves of
        // y' = (k / ((c / mu) + 1)) ** (1 / (1 - tau)) and the maximum share
        // reserves of z' = y/mu.
        let k = self.k_up();
        let mut optimal_y = k.div_up(self.c() / self.mu() + fixed!(1e18));
        if optimal_y >= fixed!(1e18) {
            // Rounding the exponent up results in a larger outcome.
            optimal_y = optimal_y.pow(fixed!(1e18).div_up(fixed!(1e18) - self.t()));
        } else {
            // Rounding the exponent down results in a larger outcome.
            optimal_y = optimal_y.pow(fixed!(1e18) / (fixed!(1e18) - self.t()));
        }

        // The optimal trade size is given by dy = y - y'.
        self.y() - optimal_y
    }

    /// Calculates the maximum amount of bonds that can be sold with the
    /// specified reserves. We round so that the max sell amount is
    /// underestimated.
    fn calculate_max_sell(&self, z_min: FixedPoint) -> FixedPoint {
        // We solve for the maximum sell using the constraint that the pool's
        // share reserves can never fall below the minimum share reserves zMin.
        // Substituting z = zMin simplifies YieldSpace to
        // k = (c / mu) * (mu * (zMin)) ** (1 - tau) + y' ** (1 - tau), and
        // gives us the maximum bond reserves of
        // y' = (k - (c / mu) * (mu * (zMin)) ** (1 - tau)) ** (1 / (1 - tau)).
        let k = self.k_down();
        let mut optimal_y = k - self.c().mul_div_up(
            self.mu().mul_up(z_min).pow(fixed!(1e18) - self.t()),
            self.mu(),
        );
        if optimal_y >= fixed!(1e18) {
            // Rounding the exponent down results in a smaller outcome.
            optimal_y = optimal_y.pow(fixed!(1e18) / (fixed!(1e18) - self.t()));
        } else {
            // Rounding the exponent up results in a smaller outcome.
            optimal_y = optimal_y.pow(fixed!(1e18).div_up(fixed!(1e18) - self.t()));
        }

        // The optimal trade size is given by dy = y' - y.
        optimal_y - self.y()
    }

    /// Calculates the YieldSpace invariant k. This invariant is given by:
    ///
    /// k = (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
    ///
    /// This variant of the calculation overestimates the result.
    fn k_up(&self) -> FixedPoint {
        self.c().mul_div_up(
            (self.mu().mul_up(self.z())).pow(fixed!(1e18) - self.t()),
            self.mu(),
        ) + self.y().pow(fixed!(1e18) - self.t())
    }

    /// Calculates the YieldSpace invariant k. This invariant is given by:
    ///
    /// k = (c / µ) * (µ * z)^(1 - t) + y^(1 - t)
    ///
    /// This variant of the calculation underestimates the result.
    fn k_down(&self) -> FixedPoint {
        self.c().mul_div_down(
            (self.mu() * self.z()).pow(fixed!(1e18) - self.t()),
            self.mu(),
        ) + self.y().pow(fixed!(1e18) - self.t())
    }
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
    async fn fuzz_calculate_bonds_out_given_shares_in() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_yield_space_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let in_ = rng.gen::<FixedPoint>();
            let actual =
                panic::catch_unwind(|| state.calculate_bonds_out_given_shares_in_down(in_));
            match mock
                .calculate_bonds_out_given_shares_in_down(
                    state.z().into(),
                    state.y().into(),
                    in_.into(),
                    (fixed!(1e18) - state.t()).into(),
                    state.c().into(),
                    state.mu().into(),
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
    async fn fuzz_calculate_shares_in_given_bonds_out_up() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_yield_space_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let in_ = rng.gen::<FixedPoint>();
            let actual = panic::catch_unwind(|| state.calculate_shares_in_given_bonds_out_up(in_));
            match mock
                .calculate_shares_in_given_bonds_out_up(
                    state.z().into(),
                    state.y().into(),
                    in_.into(),
                    (fixed!(1e18) - state.t()).into(),
                    state.c().into(),
                    state.mu().into(),
                )
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
    async fn fuzz_calculate_shares_in_given_bonds_out_down() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_yield_space_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let out = rng.gen::<FixedPoint>();
            let actual =
                panic::catch_unwind(|| state.calculate_shares_in_given_bonds_out_down(out));
            match mock
                .calculate_shares_in_given_bonds_out_down(
                    state.z().into(),
                    state.y().into(),
                    out.into(),
                    (fixed!(1e18) - state.t()).into(),
                    state.c().into(),
                    state.mu().into(),
                )
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
    async fn fuzz_calculate_shares_out_given_bonds_in_down() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_yield_space_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let in_ = rng.gen::<FixedPoint>();
            let actual =
                panic::catch_unwind(|| state.calculate_shares_out_given_bonds_in_down(in_));
            match mock
                .calculate_shares_out_given_bonds_in_down(
                    state.z().into(),
                    state.y().into(),
                    in_.into(),
                    (fixed!(1e18) - state.t()).into(),
                    state.c().into(),
                    state.mu().into(),
                )
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
    async fn fuzz_calculate_shares_out_given_bonds_in_down_safe() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_yield_space_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let in_ = rng.gen::<FixedPoint>();
            let actual =
                panic::catch_unwind(|| state.calculate_shares_out_given_bonds_in_down_safe(in_));
            match mock
                .calculate_shares_out_given_bonds_in_down_safe(
                    state.z().into(),
                    state.y().into(),
                    in_.into(),
                    (fixed!(1e18) - state.t()).into(),
                    state.c().into(),
                    state.mu().into(),
                )
                .call()
                .await
            {
                Ok((expected_out, expected_status)) => {
                    let actual = actual.unwrap();
                    assert_eq!(actual.is_ok(), expected_status);
                    assert_eq!(actual.unwrap_or(fixed!(0)), FixedPoint::from(expected_out));
                }
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_calculate_max_buy() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_yield_space_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let actual = panic::catch_unwind(|| state.calculate_max_buy());
            match mock
                .calculate_max_buy(
                    state.z().into(),
                    state.y().into(),
                    (fixed!(1e18) - state.t()).into(),
                    state.c().into(),
                    state.mu().into(),
                )
                .call()
                .await
            {
                Ok((.., expected)) => {
                    assert_eq!(actual.unwrap(), FixedPoint::from(expected));
                }
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_calculate_max_sell() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_yield_space_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let z_min = rng.gen::<FixedPoint>();
            let actual = panic::catch_unwind(|| state.calculate_max_sell(z_min));
            match mock
                .calculate_max_sell(
                    state.z().into(),
                    state.y().into(),
                    z_min.into(),
                    (fixed!(1e18) - state.t()).into(),
                    state.c().into(),
                    state.mu().into(),
                )
                .call()
                .await
            {
                Ok((.., expected)) => {
                    assert_eq!(actual.unwrap(), FixedPoint::from(expected));
                }
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_k_down() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_yield_space_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let actual = panic::catch_unwind(|| state.k_down());
            match mock
                .k_down(
                    state.z().into(),
                    state.y().into(),
                    (fixed!(1e18) - state.t()).into(),
                    state.c().into(),
                    state.mu().into(),
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
    async fn fuzz_k_up() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_yield_space_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let actual = panic::catch_unwind(|| state.k_up());
            match mock
                .k_up(
                    state.z().into(),
                    state.y().into(),
                    (fixed!(1e18) - state.t()).into(),
                    state.c().into(),
                    state.mu().into(),
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
}
