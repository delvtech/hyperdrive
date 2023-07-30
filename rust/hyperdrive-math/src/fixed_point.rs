use ethers::types::U256;
use rand::distributions::{Distribution, Standard};
use rand::Rng;

// FIXME: We should implement the Rng trait for FixedPoint so that we can
//        generate random FixedPoint numbers for testing.
#[derive(Debug, PartialEq, Eq, PartialOrd, Ord, Clone, Copy)]
struct FixedPoint(U256);

impl From<U256> for FixedPoint {
    fn from(u: U256) -> FixedPoint {
        FixedPoint(u)
    }
}

impl From<u128> for FixedPoint {
    fn from(u: u128) -> FixedPoint {
        FixedPoint(U256::from(u))
    }
}

impl From<FixedPoint> for U256 {
    fn from(f: FixedPoint) -> U256 {
        f.0
    }
}

impl From<FixedPoint> for u128 {
    fn from(f: FixedPoint) -> u128 {
        f.0.as_u128()
    }
}

impl Distribution<FixedPoint> for Standard {
    fn sample<R: Rng + ?Sized>(&self, rng: &mut R) -> FixedPoint {
        FixedPoint(U256::from(rng.gen::<[u8; 32]>()))
    }
}

// FIXME: Implement this as a math library with trait definitions for Zero, One,
// Add, Sub, Mul, Div, etc.
//
// FIXME: It's convenient to use the panics from the U256 library, but it would
// be nice to have a good way of converting this to a result during execution.
// This should become obvious when testing more.
impl FixedPoint {
    fn one() -> FixedPoint {
        FixedPoint(U256::from(10_u128).pow(U256::from(18)))
    }

    fn add(&self, other: &FixedPoint) -> FixedPoint {
        FixedPoint(self.0 + other.0)
    }

    fn sub(&self, other: &FixedPoint) -> FixedPoint {
        FixedPoint(self.0 - other.0)
    }

    // FIXME: We'll need to implement safe multiplication and division.
    fn mul_div_down(&self, other: &FixedPoint, divisor: &FixedPoint) -> FixedPoint {
        FixedPoint((self.0 * other.0) / divisor.0)
    }

    // FIXME: We'll need to implement safe multiplication and division.
    fn mul_div_up(&self, other: &FixedPoint, divisor: &FixedPoint) -> FixedPoint {
        let offset = (self.0 * other.0 % divisor.0 > U256::zero()) as u128;
        FixedPoint((self.0 * other.0) / divisor.0 + offset)
    }

    // FIXME: We'll need to implement safe multiplication and division.
    fn mul_down(&self, other: &FixedPoint) -> FixedPoint {
        self.mul_div_down(other, &FixedPoint::one())
    }

    // FIXME: We'll need to implement safe multiplication and division.
    fn mul_up(&self, other: &FixedPoint) -> FixedPoint {
        self.mul_div_up(other, &FixedPoint::one())
    }

    // FIXME: We'll need to implement safe multiplication and division.
    fn div_down(&self, other: &FixedPoint) -> FixedPoint {
        self.mul_div_down(&FixedPoint::one(), other)
    }

    // FIXME: We'll need to implement safe multiplication and division.
    fn div_up(&self, other: &FixedPoint) -> FixedPoint {
        self.mul_div_up(&FixedPoint::one(), other)
    }

    // FIXME: The next ones will be the non-trivial functions. Come back to this
    // after testing.
}

// DRY this test suite up.
#[cfg(test)]
mod tests {
    use super::*;
    use ethers::{
        contract::abigen,
        core::utils::Anvil,
        middleware::SignerMiddleware,
        providers::{Http, Provider},
        signers::{LocalWallet, Signer},
        utils::AnvilInstance,
    };
    use eyre::Result;
    use rand::{thread_rng, Rng};
    use std::{convert::TryFrom, panic, sync::Arc, time::Duration};

    // FIXME: Is there a better way of doing this?
    abigen!(
        MockFixedPointMath,
        "../../out/MockFixedPointMath.sol/MockFixedPointMath.json",
    );

    const FUZZ_RUNS: usize = 1000;

    #[tokio::test]
    async fn fuzz_add() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let a: FixedPoint = rng.gen();
            let b: FixedPoint = rng.gen();
            let actual = panic::catch_unwind(|| a.add(&b));
            match runner.mock.add(a.into(), b.into()).call().await {
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected)),
                Err(_) => {
                    let _ = actual.unwrap_err();
                }
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_sub() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let a: FixedPoint = rng.gen();
            let b: FixedPoint = rng.gen();
            let actual = panic::catch_unwind(|| a.sub(&b));
            match runner.mock.sub(a.into(), b.into()).call().await {
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected)),
                Err(_) => {
                    let _ = actual.unwrap_err();
                }
            }
        }

        Ok(())
    }

    #[test]
    fn test_mul_div_down_failure() {
        let a = FixedPoint(U256::from(10_u128).pow(U256::from(18)));
        let b = FixedPoint(U256::from(10_u128).pow(U256::from(18)));
        let c = FixedPoint(U256::from(0));
        assert!(panic::catch_unwind(|| a.mul_div_down(&b, &c)).is_err());
    }

    #[tokio::test]
    async fn fuzz_mul_div_down() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..1000 {
            let a: FixedPoint = rng.gen();
            let b: FixedPoint = rng.gen();
            let c: FixedPoint = rng.gen();
            let actual = panic::catch_unwind(|| a.mul_div_down(&b, &c));
            match runner
                .mock
                .mul_div_down(a.into(), b.into(), c.into())
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

    #[test]
    fn test_mul_div_up_failure() {
        let a = FixedPoint(U256::from(10_u128).pow(U256::from(18)));
        let b = FixedPoint(U256::from(10_u128).pow(U256::from(18)));
        let c = FixedPoint(U256::from(0));
        assert!(panic::catch_unwind(|| a.mul_div_up(&b, &c)).is_err());
    }

    #[tokio::test]
    async fn fuzz_mul_div_up() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let a: FixedPoint = rng.gen();
            let b: FixedPoint = rng.gen();
            let c: FixedPoint = rng.gen();
            let actual = panic::catch_unwind(|| a.mul_div_up(&b, &c));
            match runner
                .mock
                .mul_div_up(a.into(), b.into(), c.into())
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
    async fn fuzz_mul_down() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let a: FixedPoint = rng.gen();
            let b: FixedPoint = rng.gen();
            let actual = panic::catch_unwind(|| a.mul_down(&b));
            match runner.mock.mul_down(a.into(), b.into()).call().await {
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected)),
                Err(_) => {
                    let _ = actual.unwrap_err();
                }
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_mul_up() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let a: FixedPoint = rng.gen();
            let b: FixedPoint = rng.gen();
            let actual = panic::catch_unwind(|| a.mul_up(&b));
            match runner.mock.mul_up(a.into(), b.into()).call().await {
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected)),
                Err(_) => {
                    let _ = actual.unwrap_err();
                }
            }
        }

        Ok(())
    }

    #[test]
    fn test_div_down_failure() {
        let a = FixedPoint(U256::from(10_u128).pow(U256::from(18)));
        let b = FixedPoint(U256::from(0));
        assert!(panic::catch_unwind(|| a.div_down(&b)).is_err());
    }

    #[tokio::test]
    async fn fuzz_div_down() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let a: FixedPoint = rng.gen();
            let b: FixedPoint = rng.gen();
            let actual = panic::catch_unwind(|| a.div_down(&b));
            match runner.mock.div_down(a.into(), b.into()).call().await {
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected)),
                Err(_) => {
                    let _ = actual.unwrap_err();
                }
            }
        }

        Ok(())
    }

    #[test]
    fn test_div_up_failure() {
        let a = FixedPoint(U256::from(10_u128).pow(U256::from(18)));
        let b = FixedPoint(U256::from(0));
        assert!(panic::catch_unwind(|| a.div_up(&b)).is_err());
    }

    #[tokio::test]
    async fn fuzz_div_up() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let a: FixedPoint = rng.gen();
            let b: FixedPoint = rng.gen();
            let actual = panic::catch_unwind(|| a.div_up(&b));
            match runner.mock.div_up(a.into(), b.into()).call().await {
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected)),
                Err(_) => {
                    let _ = actual.unwrap_err();
                }
            }
        }

        Ok(())
    }

    struct TestRunner {
        mock: MockFixedPointMath<SignerMiddleware<Provider<Http>, LocalWallet>>,
        _anvil: AnvilInstance, // NOTE: Avoid dropping this until the end of the test.
    }

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
        let mock = MockFixedPointMath::deploy(client, ())?.send().await?;
        Ok(TestRunner {
            mock,
            _anvil: anvil,
        })
    }
}
