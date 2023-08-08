use fixed_point::FixedPoint;
use fixed_point_macros::fixed;
use rand::distributions::{Distribution, Standard};
use rand::Rng;

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
        let optimal_y = (self.k(t) / (self.c / self.mu + FixedPoint::one()))
            .pow(FixedPoint::one() / (FixedPoint::one() - t));
        let optimal_z = optimal_y / self.mu;

        // The optimal trade sizes are given by dz = z' - z and dy = y - y'.
        return (optimal_z - self.z, self.y - optimal_y);
    }

    pub fn k(&self, t: FixedPoint) -> FixedPoint {
        (self.c / self.mu) * (self.mu * self.z).pow(FixedPoint::one() - t)
            + self.y.pow(FixedPoint::one() - t)
    }

    fn get_bonds_out_for_shares_in(&self, in_: FixedPoint, t: FixedPoint) -> FixedPoint {
        let z = (self.c / self.mu) * (self.mu * (self.z + in_)).pow(FixedPoint::one() - t);
        let y = (self.k(t) - z).pow(FixedPoint::one().div_up(FixedPoint::one() - t));
        self.y - y
    }

    fn get_shares_out_for_bonds_in(&self, in_: FixedPoint, t: FixedPoint) -> FixedPoint {
        let y = (self.y + in_).pow(FixedPoint::one() - t);
        let mut z = (self.k(t) - y) / (self.c / self.mu);
        z = z.pow(FixedPoint::one().div_up(FixedPoint::one() - t));
        z /= self.mu;
        if self.z > z {
            self.z - z
        } else {
            FixedPoint::zero()
        }
    }

    fn get_bonds_in_for_shares_out(&self, out: FixedPoint, t: FixedPoint) -> FixedPoint {
        let z = (self.c / self.mu) * (self.mu * (self.z - out)).pow(FixedPoint::one() - t);
        let y = (self.k(t) - z).pow(FixedPoint::one().div_up(FixedPoint::one() - t));
        y - self.y
    }

    fn get_shares_in_for_bonds_out(&self, out: FixedPoint, t: FixedPoint) -> FixedPoint {
        let y = (self.y - out).pow(FixedPoint::one() - t);
        let mut z = (self.k(t) - y) / (self.c / self.mu);
        z = z.pow(FixedPoint::one().div_up(FixedPoint::one() - t));
        z /= self.mu;
        z - self.z
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ethers::{
        core::utils::Anvil,
        middleware::SignerMiddleware,
        providers::{Http, Provider},
        signers::{LocalWallet, Signer},
        utils::AnvilInstance,
    };
    use eyre::Result;
    use hyperdrive_wrappers::wrappers::mock_yield_space_math::MockYieldSpaceMath;
    use rand::{thread_rng, Rng};
    use std::{convert::TryFrom, panic, sync::Arc, time::Duration};

    const FUZZ_RUNS: usize = 10_000;

    struct TestRunner {
        mock: MockYieldSpaceMath<SignerMiddleware<Provider<Http>, LocalWallet>>,
        _anvil: AnvilInstance, // NOTE: Avoid dropping this until the end of the test.
    }

    // FIXME: DRY this up into a test-utils crate.
    //
    /// Set up a test blockchain with MockFixedPointMath deployed.
    async fn setup() -> Result<TestRunner> {
        let anvil = Anvil::new().spawn();
        let wallet: LocalWallet = anvil.keys()[0].clone().into();
        let provider =
            Provider::<Http>::try_from(anvil.endpoint())?.interval(Duration::from_millis(10u64));
        let client = Arc::new(SignerMiddleware::new(
            provider,
            wallet.with_chain_id(anvil.chain_id()),
        ));
        let mock = MockYieldSpaceMath::deploy(client, ())?.send().await?;
        Ok(TestRunner {
            mock,
            _anvil: anvil,
        })
    }

    #[test]
    fn fuzz_get_out_for_in() {
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let state = rng.gen::<State>();
            let in_ = rng.gen::<Asset>();
            let ts = rng.gen_range(FixedPoint::zero()..FixedPoint::one());
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
        for _ in 0..FUZZ_RUNS {
            let state = rng.gen::<State>();
            let out = rng.gen::<Asset>();
            let ts = rng.gen_range(FixedPoint::zero()..FixedPoint::one());
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
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let state = rng.gen::<State>();
            let ts = rng.gen_range(FixedPoint::zero()..FixedPoint::one());
            let actual = panic::catch_unwind(|| state.get_max_buy(ts));
            match runner
                .mock
                .calculate_max_buy(
                    state.z.into(),
                    state.y.into(),
                    (FixedPoint::one() - ts).into(),
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
                Err(_) => {
                    let _ = actual.unwrap_err();
                }
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_get_bonds_out_for_shares_in() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let state = rng.gen::<State>();
            let in_ = rng.gen::<FixedPoint>();
            let ts = rng.gen_range(FixedPoint::zero()..FixedPoint::one());
            let actual = panic::catch_unwind(|| state.get_bonds_out_for_shares_in(in_, ts));
            match runner
                .mock
                .calculate_bonds_out_given_shares_in(
                    state.z.into(),
                    state.y.into(),
                    in_.into(),
                    (FixedPoint::one() - ts).into(),
                    state.c.into(),
                    state.mu.into(),
                )
                .call()
                .await
            {
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected)),
                Err(_) => {
                    let _ = actual.unwrap_err();
                }
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_get_bonds_in_for_shares_out() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let state = rng.gen::<State>();
            let out = rng.gen::<FixedPoint>();
            let ts = rng.gen_range(FixedPoint::zero()..FixedPoint::one());
            let actual = panic::catch_unwind(|| state.get_bonds_in_for_shares_out(out, ts));
            match runner
                .mock
                .calculate_bonds_in_given_shares_out(
                    state.z.into(),
                    state.y.into(),
                    out.into(),
                    (FixedPoint::one() - ts).into(),
                    state.c.into(),
                    state.mu.into(),
                )
                .call()
                .await
            {
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected)),
                Err(_) => {
                    let _ = actual.unwrap_err();
                }
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_get_shares_out_for_bonds_in() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let state = rng.gen::<State>();
            let in_ = rng.gen::<FixedPoint>();
            let ts = rng.gen_range(FixedPoint::zero()..FixedPoint::one());
            let actual = panic::catch_unwind(|| state.get_shares_out_for_bonds_in(in_, ts));
            match runner
                .mock
                .calculate_shares_out_given_bonds_in(
                    state.z.into(),
                    state.y.into(),
                    in_.into(),
                    (FixedPoint::one() - ts).into(),
                    state.c.into(),
                    state.mu.into(),
                )
                .call()
                .await
            {
                Ok(expected) => {
                    assert_eq!(actual.unwrap(), FixedPoint::from(expected));
                }
                Err(_) => {
                    let _ = actual.unwrap_err();
                }
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_get_shares_in_for_bonds_out() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let state = rng.gen::<State>();
            let out = rng.gen::<FixedPoint>();
            let ts = rng.gen_range(FixedPoint::zero()..FixedPoint::one());
            let actual = panic::catch_unwind(|| state.get_shares_in_for_bonds_out(out, ts));
            match runner
                .mock
                .calculate_shares_in_given_bonds_out(
                    state.z.into(),
                    state.y.into(),
                    out.into(),
                    (FixedPoint::one() - ts).into(),
                    state.c.into(),
                    state.mu.into(),
                )
                .call()
                .await
            {
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected)),
                Err(_) => {
                    let _ = actual.unwrap_err();
                }
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_k() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let state = rng.gen::<State>();
            let ts = rng.gen_range(FixedPoint::zero()..FixedPoint::one());
            let actual = panic::catch_unwind(|| state.k(ts));
            match runner
                .mock
                .modified_yield_space_constant(
                    (state.c / state.mu).into(),
                    state.mu.into(),
                    state.z.into(),
                    (FixedPoint::one() - ts).into(),
                    state.y.into(),
                )
                .call()
                .await
            {
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected)),
                Err(_) => {
                    let _ = actual.unwrap_err();
                }
            }
        }

        Ok(())
    }
}
