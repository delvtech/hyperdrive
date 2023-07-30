use ethers::types::{I256, U256};
use rand::distributions::{Distribution, Standard};
use rand::Rng;
use std::ops::{BitOr, Shl, Shr};

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

    fn mul_div_down(&self, other: &FixedPoint, divisor: &FixedPoint) -> FixedPoint {
        FixedPoint((self.0 * other.0) / divisor.0)
    }

    fn mul_div_up(&self, other: &FixedPoint, divisor: &FixedPoint) -> FixedPoint {
        let offset = (self.0 * other.0 % divisor.0 > U256::zero()) as u128;
        FixedPoint((self.0 * other.0) / divisor.0 + offset)
    }

    fn mul_down(&self, other: &FixedPoint) -> FixedPoint {
        self.mul_div_down(other, &FixedPoint::one())
    }

    fn mul_up(&self, other: &FixedPoint) -> FixedPoint {
        self.mul_div_up(other, &FixedPoint::one())
    }

    fn div_down(&self, other: &FixedPoint) -> FixedPoint {
        self.mul_div_down(&FixedPoint::one(), other)
    }

    fn div_up(&self, other: &FixedPoint) -> FixedPoint {
        self.mul_div_up(&FixedPoint::one(), other)
    }

    // FIXME: Implement the remaining functions.

    // TODO: Document this to make it more understandable. Part of the exercise
    // is getting a better understanding of the details.
    fn ln(mut x: I256) -> I256 {
        if x <= I256::zero() {
            panic!("ln of negative number or zero");
        }

        let mut r: I256 =
            I256::from((x > I256::from(0xffffffffffffffffffffffffffffffff_u128)) as u128)
                .wrapping_shl(7);
        r = r.bitor(
            I256::from(((x >> r.as_usize()) > I256::from(0xffffffffffffffff_u128)) as u128)
                .wrapping_shl(6),
        );
        r = r.bitor(
            I256::from(((x >> r.as_usize()) > I256::from(0xffffffff_u128)) as u128).wrapping_shl(5),
        );
        r = r.bitor(
            I256::from(((x >> r.as_usize()) > I256::from(0xffff_u128)) as u128).wrapping_shl(4),
        );
        r = r.bitor(
            I256::from(((x >> r.as_usize()) > I256::from(0xff_u128)) as u128).wrapping_shl(3),
        );
        r = r.bitor(
            I256::from(((x >> r.as_usize()) > I256::from(0xf_u128)) as u128).wrapping_shl(2),
        );
        r = r.bitor(
            I256::from(((x >> r.as_usize()) > I256::from(0x3_u128)) as u128).wrapping_shl(1),
        );
        r = r.bitor(I256::from(
            (x.wrapping_shr(r.as_usize()) > I256::from(0x1_u128)) as u128,
        ));

        let k: I256 = r.wrapping_sub(I256::from(96));
        x = x.wrapping_shl(I256::from(159).wrapping_sub(k).as_usize());
        x = x.wrapping_shr(159);

        let mut p: I256 = x.wrapping_add(I256::from(3273285459638523848632254066296_u128));
        p = ((p.wrapping_mul(x)).wrapping_shr(96))
            .wrapping_add(I256::from(24828157081833163892658089445524_u128));
        p = ((p.wrapping_mul(x)).wrapping_shr(96))
            .wrapping_add(I256::from(43456485725739037958740375743393_u128));
        p = ((p.wrapping_mul(x)).wrapping_shr(96))
            .wrapping_sub(I256::from(11111509109440967052023855526967_u128));
        p = ((p.wrapping_mul(x)).wrapping_shr(96))
            .wrapping_sub(I256::from(45023709667254063763336534515857_u128));
        p = ((p.wrapping_mul(x)).wrapping_shr(96))
            .wrapping_sub(I256::from(14706773417378608786704636184526_u128));
        p = p
            .wrapping_mul(x)
            .wrapping_sub(I256::from(795164235651350426258249787498_u128).wrapping_shl(96));

        let mut q: I256 = x.wrapping_add(I256::from(5573035233440673466300451813936_u128));
        q = (q.wrapping_mul(x).wrapping_shr(96))
            .wrapping_add(I256::from(71694874799317883764090561454958_u128));
        q = q
            .wrapping_mul(x)
            .wrapping_shr(96)
            .wrapping_add(I256::from(283447036172924575727196451306956_u128));
        q = q
            .wrapping_mul(x)
            .wrapping_shr(96)
            .wrapping_add(I256::from(401686690394027663651624208769553_u128));
        q = q
            .wrapping_mul(x)
            .wrapping_shr(96)
            .wrapping_add(I256::from(204048457590392012362485061816622_u128));
        q = q
            .wrapping_mul(x)
            .wrapping_shr(96)
            .wrapping_add(I256::from(31853899698501571402653359427138_u128));
        q = q
            .wrapping_mul(x)
            .wrapping_shr(96)
            .wrapping_add(I256::from(909429971244387300277376558375_u128));

        r = p / q;

        // FIXME: Can we avoid string conversions here? This is going to slow us down.
        r = r.wrapping_mul(I256::from_raw(U256::from(
            "0x00000000000000000000000000001340daa0d5f769dba1915cef59f0815a5506",
        )));
        r = r.wrapping_add(
            I256::from_raw(U256::from(
                "0x00000267a36c0c95b3975ab3ee5b203a7614a3f75373f047d803ae7b6687f2b3",
            ))
            .wrapping_mul(k),
        );
        r = r.wrapping_add(I256::from_raw(U256::from(
            "0x000057115e47018c7177eebf7cd370a3356a1b7863008a5ae8028c72b8864284",
        )));
        r = r.wrapping_shr(174);

        r
    }
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

    const FUZZ_RUNS: usize = 10_000;

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

    #[tokio::test]
    async fn fuzz_ln() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let x: I256 = I256::from_raw(rng.gen::<FixedPoint>().0);
            let actual = panic::catch_unwind(|| FixedPoint::ln(x));
            match runner.mock.ln(x).call().await {
                Ok(expected) => assert_eq!(actual.unwrap(), expected),
                Err(_) => {
                    let _ = actual.unwrap_err();
                }
            }
        }

        Ok(())
    }
}
