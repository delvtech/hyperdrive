use fixed_point::FixedPoint;
use fixed_point_macros::fixed;

use crate::Asset;

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

    fn get_out_for_in(&self, in_: Asset) -> FixedPoint {
        match in_ {
            Asset::Shares(in_) => self.get_bonds_out_for_shares_in(in_, private::Seal),
            Asset::Bonds(in_) => self.get_shares_out_for_bonds_in(in_, private::Seal),
        }
    }

    fn get_out_for_in_safe(&self, in_: Asset) -> Option<FixedPoint> {
        match in_ {
            // TODO: Make this safer as needed.
            Asset::Shares(in_) => Some(self.get_bonds_out_for_shares_in(in_, private::Seal)),
            Asset::Bonds(in_) => self.get_shares_out_for_bonds_in_safe(in_, private::Seal),
        }
    }

    fn get_in_for_out(&self, out: Asset) -> FixedPoint {
        match out {
            Asset::Shares(out) => self.get_bonds_in_for_shares_out(out, private::Seal),
            Asset::Bonds(out) => self.get_shares_in_for_bonds_out(out, private::Seal),
        }
    }

    fn get_max_buy(&self) -> (FixedPoint, FixedPoint) {
        // We solve for the maximum buy using the constraint that the pool's
        // spot price can never exceed 1. We do this by noting that a spot price
        // of 1, (mu * z) / y ** tau = 1, implies that mu * z = y. This
        // simplifies YieldSpace to k = ((c / mu) + 1) * y ** (1 - tau), and
        // gives us the maximum bond reserves of y' = (k / ((c / mu) + 1)) ** (1 / (1 - tau))
        // and the maximum share reserves of z' = y/mu.
        let optimal_y = (self.k() / (self.c() / self.mu() + fixed!(1e18)))
            .pow(fixed!(1e18) / (fixed!(1e18) - self.t()));
        let optimal_z = optimal_y / self.mu();

        // The optimal trade sizes are given by dz = z' - z and dy = y - y'.
        (optimal_z - self.z(), self.y() - optimal_y)
    }

    fn k(&self) -> FixedPoint {
        (self.c() / self.mu()) * (self.mu() * self.z()).pow(fixed!(1e18) - self.t())
            + self.y().pow(fixed!(1e18) - self.t())
    }

    /// Helpers ///

    fn get_bonds_out_for_shares_in(&self, in_: FixedPoint, _: private::Seal) -> FixedPoint {
        let z =
            (self.c() / self.mu()) * (self.mu() * (self.z() + in_)).pow(fixed!(1e18) - self.t());
        let y = (self.k() - z).pow(fixed!(1e18).div_up(fixed!(1e18) - self.t()));
        self.y() - y
    }

    fn get_shares_out_for_bonds_in(&self, in_: FixedPoint, seal: private::Seal) -> FixedPoint {
        self.get_shares_out_for_bonds_in_safe(in_, seal).unwrap()
    }

    fn get_shares_out_for_bonds_in_safe(
        &self,
        in_: FixedPoint,
        _: private::Seal,
    ) -> Option<FixedPoint> {
        let y = (self.y() + in_).pow(fixed!(1e18) - self.t());
        if self.k() < y {
            return None;
        }
        let mut z = (self.k() - y) / (self.c() / self.mu());
        z = z.pow(fixed!(1e18).div_up(fixed!(1e18) - self.t()));
        z /= self.mu();
        if self.z() > z {
            Some(self.z() - z)
        } else {
            Some(fixed!(0))
        }
    }

    fn get_bonds_in_for_shares_out(&self, out: FixedPoint, _: private::Seal) -> FixedPoint {
        let z =
            (self.c() / self.mu()) * (self.mu() * (self.z() - out)).pow(fixed!(1e18) - self.t());
        let y = (self.k() - z).pow(fixed!(1e18).div_up(fixed!(1e18) - self.t()));
        y - self.y()
    }

    fn get_shares_in_for_bonds_out(&self, out: FixedPoint, _: private::Seal) -> FixedPoint {
        let y = (self.y() - out).pow(fixed!(1e18) - self.t());
        let mut z = (self.k() - y) / (self.c() / self.mu());
        z = z.pow(fixed!(1e18).div_up(fixed!(1e18) - self.t()));
        z /= self.mu();
        z - self.z()
    }
}

mod private {
    pub struct Seal;
}

#[cfg(test)]
mod tests {
    use std::panic;

    use eyre::Result;
    use rand::{thread_rng, Rng};
    use test_utils::{chain::TestChainWithMocks, constants::FAST_FUZZ_RUNS};

    use super::*;
    use crate::State;

    #[test]
    fn fuzz_get_out_for_in() {
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let in_ = rng.gen::<Asset>();
            let expected = match in_ {
                Asset::Shares(in_) => {
                    panic::catch_unwind(|| state.get_bonds_out_for_shares_in(in_, private::Seal))
                }
                Asset::Bonds(in_) => {
                    panic::catch_unwind(|| state.get_shares_out_for_bonds_in(in_, private::Seal))
                }
            };
            let actual = panic::catch_unwind(|| state.get_out_for_in(in_));
            match expected {
                Ok(expected) => assert_eq!(actual.unwrap(), expected),
                Err(_) => assert!(actual.is_err()),
            }
        }
    }

    #[test]
    fn fuzz_get_in_for_out() {
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let out = rng.gen::<Asset>();
            let expected = match out {
                Asset::Shares(out) => {
                    panic::catch_unwind(|| state.get_bonds_in_for_shares_out(out, private::Seal))
                }
                Asset::Bonds(out) => {
                    panic::catch_unwind(|| state.get_shares_in_for_bonds_out(out, private::Seal))
                }
            };
            let actual = panic::catch_unwind(|| state.get_in_for_out(out));
            match expected {
                Ok(expected) => assert_eq!(actual.unwrap(), expected),
                Err(_) => assert!(actual.is_err()),
            }
        }
    }

    #[tokio::test]
    async fn fuzz_get_max_buy() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_yield_space_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let actual = panic::catch_unwind(|| state.get_max_buy());
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
                Ok((expected_dz, expected_dy)) => {
                    let (actual_dz, actual_dy) = actual.unwrap();
                    assert_eq!(actual_dz, FixedPoint::from(expected_dz));
                    assert_eq!(actual_dy, FixedPoint::from(expected_dy));
                }
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_get_bonds_out_for_shares_in() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_yield_space_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let in_ = rng.gen::<FixedPoint>();
            let actual =
                panic::catch_unwind(|| state.get_bonds_out_for_shares_in(in_, private::Seal));
            match mock
                .calculate_bonds_out_given_shares_in(
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
    async fn fuzz_get_bonds_in_for_shares_out() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_yield_space_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let out = rng.gen::<FixedPoint>();
            let actual =
                panic::catch_unwind(|| state.get_bonds_in_for_shares_out(out, private::Seal));
            match mock
                .calculate_bonds_in_given_shares_out(
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
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected)),
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_get_shares_out_for_bonds_in() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_yield_space_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let in_ = rng.gen::<FixedPoint>();
            let actual =
                panic::catch_unwind(|| state.get_shares_out_for_bonds_in(in_, private::Seal));
            match mock
                .calculate_shares_out_given_bonds_in(
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
    async fn fuzz_get_shares_in_for_bonds_out() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_yield_space_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let out = rng.gen::<FixedPoint>();
            let actual =
                panic::catch_unwind(|| state.get_shares_in_for_bonds_out(out, private::Seal));
            match mock
                .calculate_shares_in_given_bonds_out(
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
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected)),
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_k() -> Result<()> {
        let chain = TestChainWithMocks::new(1).await?;
        let mock = chain.mock_yield_space_math();

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let actual = panic::catch_unwind(|| state.k());
            match mock
                .modified_yield_space_constant(
                    (state.c() / state.mu()).into(),
                    state.mu().into(),
                    state.z().into(),
                    (fixed!(1e18) - state.t()).into(),
                    state.y().into(),
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
