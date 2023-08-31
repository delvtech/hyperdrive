use ethers::types::U256;
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, uint256};
use rand::{
    distributions::{Distribution, Standard},
    Rng,
};

#[derive(Debug, PartialEq, Eq, PartialOrd, Ord, Clone, Copy)]
pub enum Asset {
    Shares(FixedPoint),
    Bonds(FixedPoint),
}

impl Distribution<Asset> for Standard {
    fn sample<R: Rng + ?Sized>(&self, rng: &mut R) -> Asset {
        let content = rng.gen::<FixedPoint>();
        if rng.gen::<bool>() {
            Asset::Shares(content)
        } else {
            Asset::Bonds(content)
        }
    }
}

#[derive(Debug)]
pub struct State {
    z: FixedPoint,
    y: FixedPoint,
    c: FixedPoint,
    mu: FixedPoint,
}

impl Distribution<State> for Standard {
    // TODO: It may be better for this to be a uniform sampler and have a test
    // sampler that is more restrictive like this.
    fn sample<R: Rng + ?Sized>(&self, rng: &mut R) -> State {
        State {
            z: rng.gen_range(fixed!(0)..=fixed!(1_000_000_000e18)),
            y: rng.gen_range(fixed!(0)..=fixed!(1_000_000_000e18)),
            c: rng.gen_range(fixed!(0.5e18)..=fixed!(5e18)),
            mu: rng.gen_range(fixed!(0.5e18)..=fixed!(5e18)),
        }
    }
}

// TODO: Document all of the math in this library. Since this is our
// reference implementation, we should strive to make it as clear as possible.
impl State {
    pub fn new(z: FixedPoint, y: FixedPoint, c: FixedPoint, mu: FixedPoint) -> Self {
        Self { z, y, c, mu }
    }

    pub fn get_spot_price(&self, t: FixedPoint) -> FixedPoint {
        ((self.mu * self.z) / self.y).pow(t)
    }

    pub fn get_out_for_in(&self, in_: Asset, t: FixedPoint) -> FixedPoint {
        match in_ {
            Asset::Shares(in_) => self.get_bonds_out_for_shares_in(in_, t),
            Asset::Bonds(in_) => self.get_shares_out_for_bonds_in(in_, t),
        }
    }

    pub fn get_in_for_out(&self, out: Asset, t: FixedPoint) -> FixedPoint {
        match out {
            Asset::Shares(out) => self.get_bonds_in_for_shares_out(out, t),
            Asset::Bonds(out) => self.get_shares_in_for_bonds_out(out, t),
        }
    }

    pub fn get_max_buy(&self, t: FixedPoint) -> (FixedPoint, FixedPoint) {
        // We solve for the maximum buy using the constraint that the pool's
        // spot price can never exceed 1. We do this by noting that a spot price
        // of 1, (mu * z) / y ** tau = 1, implies that mu * z = y. This
        // simplifies YieldSpace to k = ((c / mu) + 1) * y ** (1 - tau), and
        // gives us the maximum bond reserves of y' = (k / ((c / mu) + 1)) ** (1 / (1 - tau))
        // and the maximum share reserves of z' = y/mu.
        let optimal_y =
            (self.k(t) / (self.c / self.mu + fixed!(1e18))).pow(fixed!(1e18) / (fixed!(1e18) - t));
        let optimal_z = optimal_y / self.mu;

        // The optimal trade sizes are given by dz = z' - z and dy = y - y'.
        (optimal_z - self.z, self.y - optimal_y)
    }

    pub fn k(&self, t: FixedPoint) -> FixedPoint {
        (self.c / self.mu) * (self.mu * self.z).pow(fixed!(1e18) - t) + self.y.pow(fixed!(1e18) - t)
    }

    fn get_bonds_out_for_shares_in(&self, in_: FixedPoint, t: FixedPoint) -> FixedPoint {
        let z = (self.c / self.mu) * (self.mu * (self.z + in_)).pow(fixed!(1e18) - t);
        let y = (self.k(t) - z).pow(fixed!(1e18).div_up(fixed!(1e18) - t));
        self.y - y
    }

    fn get_shares_out_for_bonds_in(&self, in_: FixedPoint, t: FixedPoint) -> FixedPoint {
        let y = (self.y + in_).pow(fixed!(1e18) - t);
        let mut z = (self.k(t) - y) / (self.c / self.mu);
        z = z.pow(fixed!(1e18).div_up(fixed!(1e18) - t));
        z /= self.mu;
        if self.z > z {
            self.z - z
        } else {
            fixed!(0)
        }
    }

    fn get_bonds_in_for_shares_out(&self, out: FixedPoint, t: FixedPoint) -> FixedPoint {
        let z = (self.c / self.mu) * (self.mu * (self.z - out)).pow(fixed!(1e18) - t);
        let y = (self.k(t) - z).pow(fixed!(1e18).div_up(fixed!(1e18) - t));
        y - self.y
    }

    fn get_shares_in_for_bonds_out(&self, out: FixedPoint, t: FixedPoint) -> FixedPoint {
        let y = (self.y - out).pow(fixed!(1e18) - t);
        let mut z = (self.k(t) - y) / (self.c / self.mu);
        z = z.pow(fixed!(1e18).div_up(fixed!(1e18) - t));
        z /= self.mu;
        z - self.z
    }
}

impl State {
    pub fn get_time_stretch(mut rate: FixedPoint) -> FixedPoint {
        rate = (U256::from(rate) * uint256!(100)).into();
        let time_stretch = fixed!(5.24592e18) / (fixed!(0.04665e18) * rate);
        fixed!(1e18) / time_stretch
    }
}

#[cfg(test)]
mod tests {
    use std::panic;

    use eyre::Result;
    use rand::{thread_rng, Rng};
    use test_utils::{chain::TestChainWithMocks, constants::FAST_FUZZ_RUNS};

    use super::*;

    #[test]
    fn fuzz_get_out_for_in() {
        let mut rng = thread_rng();
        for _ in 0..*FAST_FUZZ_RUNS {
            let state = rng.gen::<State>();
            let in_ = rng.gen::<Asset>();
            let ts = rng.gen_range(fixed!(0)..fixed!(1e18));
            let expected = match in_ {
                Asset::Shares(in_) => {
                    panic::catch_unwind(|| state.get_bonds_out_for_shares_in(in_, ts))
                }
                Asset::Bonds(in_) => {
                    panic::catch_unwind(|| state.get_shares_out_for_bonds_in(in_, ts))
                }
            };
            let actual = panic::catch_unwind(|| state.get_out_for_in(in_, ts));
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
            let ts = rng.gen_range(fixed!(0)..fixed!(1e18));
            let expected = match out {
                Asset::Shares(out) => {
                    panic::catch_unwind(|| state.get_bonds_in_for_shares_out(out, ts))
                }
                Asset::Bonds(out) => {
                    panic::catch_unwind(|| state.get_shares_in_for_bonds_out(out, ts))
                }
            };
            let actual = panic::catch_unwind(|| state.get_in_for_out(out, ts));
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
            let ts = rng.gen_range(fixed!(0)..fixed!(1e18));
            let actual = panic::catch_unwind(|| state.get_max_buy(ts));
            match mock
                .calculate_max_buy(
                    state.z.into(),
                    state.y.into(),
                    (fixed!(1e18) - ts).into(),
                    state.c.into(),
                    state.mu.into(),
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
            let ts = rng.gen_range(fixed!(0)..fixed!(1e18));
            let actual = panic::catch_unwind(|| state.get_bonds_out_for_shares_in(in_, ts));
            match mock
                .calculate_bonds_out_given_shares_in(
                    state.z.into(),
                    state.y.into(),
                    in_.into(),
                    (fixed!(1e18) - ts).into(),
                    state.c.into(),
                    state.mu.into(),
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
            let ts = rng.gen_range(fixed!(0)..fixed!(1e18));
            let actual = panic::catch_unwind(|| state.get_bonds_in_for_shares_out(out, ts));
            match mock
                .calculate_bonds_in_given_shares_out(
                    state.z.into(),
                    state.y.into(),
                    out.into(),
                    (fixed!(1e18) - ts).into(),
                    state.c.into(),
                    state.mu.into(),
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
            let ts = rng.gen_range(fixed!(0)..fixed!(1e18));
            let actual = panic::catch_unwind(|| state.get_shares_out_for_bonds_in(in_, ts));
            match mock
                .calculate_shares_out_given_bonds_in(
                    state.z.into(),
                    state.y.into(),
                    in_.into(),
                    (fixed!(1e18) - ts).into(),
                    state.c.into(),
                    state.mu.into(),
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
            let ts = rng.gen_range(fixed!(0)..fixed!(1e18));
            let actual = panic::catch_unwind(|| state.get_shares_in_for_bonds_out(out, ts));
            match mock
                .calculate_shares_in_given_bonds_out(
                    state.z.into(),
                    state.y.into(),
                    out.into(),
                    (fixed!(1e18) - ts).into(),
                    state.c.into(),
                    state.mu.into(),
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
            let ts = rng.gen_range(fixed!(0)..fixed!(1e18));
            let actual = panic::catch_unwind(|| state.k(ts));
            match mock
                .modified_yield_space_constant(
                    (state.c / state.mu).into(),
                    state.mu.into(),
                    state.z.into(),
                    (fixed!(1e18) - ts).into(),
                    state.y.into(),
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
