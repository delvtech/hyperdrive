use ethers::types::{I256, U256};
use fixed_point_macros::{fixed, int256, uint256};
use rand::distributions::uniform::{SampleBorrow, SampleUniform, UniformSampler};
use rand::distributions::{Distribution, Standard};
use rand::Rng;
use std::ops::{Add, AddAssign, Div, DivAssign, Mul, MulAssign, Shr, Sub, SubAssign};

#[derive(Debug, Default, PartialEq, Eq, PartialOrd, Ord, Clone, Copy)]
pub struct FixedPoint(U256);

impl From<I256> for FixedPoint {
    fn from(i: I256) -> FixedPoint {
        i.into_raw().into()
    }
}

impl From<[u8; 32]> for FixedPoint {
    fn from(bytes: [u8; 32]) -> FixedPoint {
        U256::from(bytes).into()
    }
}

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

impl From<FixedPoint> for u128 {
    fn from(f: FixedPoint) -> u128 {
        f.0.as_u128()
    }
}

impl From<FixedPoint> for U256 {
    fn from(f: FixedPoint) -> U256 {
        f.0
    }
}

impl From<FixedPoint> for I256 {
    fn from(f: FixedPoint) -> I256 {
        I256::from_raw(f.0)
    }
}

impl Add for FixedPoint {
    type Output = FixedPoint;

    fn add(self, other: FixedPoint) -> FixedPoint {
        FixedPoint(self.0 + other.0)
    }
}

impl AddAssign for FixedPoint {
    fn add_assign(&mut self, other: FixedPoint) {
        *self = *self + other;
    }
}

impl Sub for FixedPoint {
    type Output = FixedPoint;

    fn sub(self, other: FixedPoint) -> FixedPoint {
        FixedPoint(self.0 - other.0)
    }
}

impl SubAssign for FixedPoint {
    fn sub_assign(&mut self, other: FixedPoint) {
        *self = *self - other;
    }
}

/// The operator overloaded multiplication is the version that rounds down. A
/// `mul_up` function is also available.
impl Mul for FixedPoint {
    type Output = FixedPoint;

    fn mul(self, other: FixedPoint) -> FixedPoint {
        self.mul_down(other)
    }
}

impl MulAssign for FixedPoint {
    fn mul_assign(&mut self, other: FixedPoint) {
        *self = *self * other;
    }
}

/// The operator overloaded multiplication is the version that rounds down. A
/// `div_up` function is also available.
impl Div for FixedPoint {
    type Output = FixedPoint;

    fn div(self, other: FixedPoint) -> FixedPoint {
        self.div_down(other)
    }
}

impl DivAssign for FixedPoint {
    fn div_assign(&mut self, other: FixedPoint) {
        *self = *self / other;
    }
}

/// This impl is a direct port of Solidity's FixedPointMath library.
impl FixedPoint {
    pub fn mul_div_down(self, other: FixedPoint, divisor: FixedPoint) -> FixedPoint {
        FixedPoint((self.0 * other.0) / divisor.0)
    }

    pub fn mul_div_up(self, other: FixedPoint, divisor: FixedPoint) -> FixedPoint {
        let offset = (self.0 * other.0 % divisor.0 > U256::zero()) as u128;
        FixedPoint((self.0 * other.0) / divisor.0 + offset)
    }

    pub fn mul_down(self, other: FixedPoint) -> FixedPoint {
        self.mul_div_down(other, fixed!(1e18))
    }

    pub fn mul_up(self, other: FixedPoint) -> FixedPoint {
        self.mul_div_up(other, fixed!(1e18))
    }

    pub fn div_down(self, other: FixedPoint) -> FixedPoint {
        self.mul_div_down(fixed!(1e18), other)
    }

    pub fn div_up(self, other: FixedPoint) -> FixedPoint {
        self.mul_div_up(fixed!(1e18), other)
    }

    pub fn pow(self, y: FixedPoint) -> FixedPoint {
        // If the exponent is 0, return 1.
        if y == fixed!(0) {
            return fixed!(1e18);
        }

        // If the base is 0, return 0.
        if self == fixed!(0) {
            return fixed!(0);
        }

        // Using properties of logarithms we calculate x^y:
        // -> ln(x^y) = y * ln(x)
        // -> e^(y * ln(x)) = x^y
        let y_int256 = I256::from(y);

        // Compute y*ln(x)
        // Any overflow for x will be caught in _ln() in the initial bounds check
        let lnx: I256 = Self::ln(I256::from(self));
        let mut ylnx: I256 = y_int256.wrapping_mul(lnx);
        ylnx = ylnx.wrapping_div(int256!(1e18));

        // Calculate exp(y * ln(x)) to get x^y
        Self::exp(ylnx).into()
    }

    fn exp(mut x: I256) -> I256 {
        // When the result is < 0.5 we return zero. This happens when
        // x <= floor(log(0.5e18) * 1e18) ~ -42e18
        if x <= int256!(-42139678854452767551) {
            return I256::zero();
        }

        // When the result is > (2**255 - 1) / 1e18 we can not represent it as an
        // int. This happens when x >= floor(log((2**255 - 1) / 1e18) * 1e18) ~ 135.
        if x >= int256!(135305999368893231589) {
            panic!("invalid exponent");
        }

        // x is now in the range (-42, 136) * 1e18. Convert to (-42, 136) * 2**96
        // for more intermediate precision and a binary basis. This base conversion
        // is a multiplication by 1e18 / 2**96 = 5**18 / 2**78.
        x = x.wrapping_shl(78) / int256!(5).pow(18);

        // Reduce range of x to (-½ ln 2, ½ ln 2) * 2**96 by factoring out powers
        // of two such that exp(x) = exp(x') * 2**k, where k is an integer.
        // Solving this gives k = round(x / log(2)) and x' = x - k * log(2).
        let k: I256 = ((x.wrapping_shl(96) / int256!(54916777467707473351141471128))
            .wrapping_add(int256!(2).pow(95)))
        .asr(96);
        x = x.wrapping_sub(k.wrapping_mul(54916777467707473351141471128_u128.into()));

        // k is in the range [-61, 195].

        // Evaluate using a (6, 7)-term rational approximation.
        // p is made monic, we'll multiply by a scale factor later.
        let mut y: I256 = x.wrapping_add(1346386616545796478920950773328_u128.into());
        y = y
            .wrapping_mul(x)
            .asr(96)
            .wrapping_add(57155421227552351082224309758442_u128.into());
        let mut p: I256 = y
            .wrapping_add(x)
            .wrapping_sub(94201549194550492254356042504812_u128.into());
        p = p
            .wrapping_mul(y)
            .asr(96)
            .wrapping_add(28719021644029726153956944680412240_u128.into());
        p = p
            .wrapping_mul(x)
            .wrapping_add(int256!(4385272521454847904659076985693276_u128).wrapping_shl(96));

        // We leave p in 2**192 basis so we don't need to scale it back up for the division.
        let mut q: I256 = x.wrapping_sub(2855989394907223263936484059900_u128.into());
        q = q
            .wrapping_mul(x)
            .asr(96)
            .wrapping_add(50020603652535783019961831881945_u128.into());
        q = q
            .wrapping_mul(x)
            .asr(96)
            .wrapping_sub(533845033583426703283633433725380_u128.into());
        q = q
            .wrapping_mul(x)
            .asr(96)
            .wrapping_add(3604857256930695427073651918091429_u128.into());
        q = q
            .wrapping_mul(x)
            .asr(96)
            .wrapping_sub(14423608567350463180887372962807573_u128.into());
        q = q
            .wrapping_mul(x)
            .asr(96)
            .wrapping_add(26449188498355588339934803723976023_u128.into());

        let mut r = p.wrapping_div(q);

        // r should be in the range (0.09, 0.25) * 2**96.

        // We now need to multiply r by:
        // * the scale factor s = ~6.031367120.
        // * the 2**k factor from the range reduction.
        // * the 1e18 / 2**96 factor for base conversion.
        // We do this all at once, with an intermediate result in 2**213
        // basis, so the final right shift is always by a positive amount.
        r = I256::from_raw(
            (r.into_raw()
                .overflowing_mul(uint256!(3822833074963236453042738258902158003155416615667))
                .0)
                .shr(int256!(195).wrapping_sub(k).low_usize()),
        );

        r
    }

    fn ln(mut x: I256) -> I256 {
        if x <= I256::zero() {
            panic!("ln of negative number or zero");
        }

        // We want to convert x from 10**18 fixed point to 2**96 fixed point.
        // We do this by multiplying by 2**96 / 10**18. But since
        // ln(x * C) = ln(x) + ln(C), we can simply do nothing here
        // and add ln(2**96 / 10**18) at the end.

        let mut r: I256 =
            I256::from((x > I256::from(0xffffffffffffffffffffffffffffffff_u128)) as u128)
                .wrapping_shl(7);
        r = r | I256::from((x.asr(r.as_usize()) > I256::from(0xffffffffffffffff_u128)) as u128)
            .wrapping_shl(6);
        r = r | I256::from((x.asr(r.as_usize()) > I256::from(0xffffffff_u128)) as u128)
            .wrapping_shl(5);
        r = r | I256::from((x.asr(r.as_usize()) > I256::from(0xffff_u128)) as u128).wrapping_shl(4);
        r = r | I256::from((x.asr(r.as_usize()) > I256::from(0xff_u128)) as u128).wrapping_shl(3);
        r = r | I256::from((x.asr(r.as_usize()) > I256::from(0xf_u128)) as u128).wrapping_shl(2);
        r = r | I256::from((x.asr(r.as_usize()) > I256::from(0x3_u128)) as u128).wrapping_shl(1);
        r = r | I256::from((x.asr(r.as_usize()) > I256::from(0x1_u128)) as u128);

        // Reduce range of x to (1, 2) * 2**96
        // ln(2^k * x) = k * ln(2) + ln(x)
        let k: I256 = r.wrapping_sub(int256!(96));
        x = x.wrapping_shl(int256!(159).wrapping_sub(k).as_usize());
        x = I256::from_raw(x.into_raw().shr(159));

        // Evaluate using a (8, 8)-term rational approximation.
        // p is made monic, we will multiply by a scale factor later.
        let mut p: I256 = x.wrapping_add(int256!(3273285459638523848632254066296));
        p = ((p.wrapping_mul(x)).asr(96)).wrapping_add(int256!(24828157081833163892658089445524));
        p = ((p.wrapping_mul(x)).asr(96)).wrapping_add(int256!(43456485725739037958740375743393));
        p = ((p.wrapping_mul(x)).asr(96)).wrapping_sub(int256!(11111509109440967052023855526967));
        p = ((p.wrapping_mul(x)).asr(96)).wrapping_sub(int256!(45023709667254063763336534515857));
        p = ((p.wrapping_mul(x)).asr(96)).wrapping_sub(int256!(14706773417378608786704636184526));
        p = p
            .wrapping_mul(x)
            .wrapping_sub(int256!(795164235651350426258249787498).wrapping_shl(96));

        // We leave p in 2**192 basis so we don't need to scale it back up for the division.
        // q is monic by convention.
        let mut q: I256 = x.wrapping_add(int256!(5573035233440673466300451813936));
        q = (q.wrapping_mul(x).asr(96)).wrapping_add(int256!(71694874799317883764090561454958));
        q = q
            .wrapping_mul(x)
            .asr(96)
            .wrapping_add(int256!(283447036172924575727196451306956));
        q = q
            .wrapping_mul(x)
            .asr(96)
            .wrapping_add(int256!(401686690394027663651624208769553));
        q = q
            .wrapping_mul(x)
            .asr(96)
            .wrapping_add(int256!(204048457590392012362485061816622));
        q = q
            .wrapping_mul(x)
            .asr(96)
            .wrapping_add(int256!(31853899698501571402653359427138));
        q = q
            .wrapping_mul(x)
            .asr(96)
            .wrapping_add(int256!(909429971244387300277376558375));

        r = p.wrapping_div(q);

        // r is in the range (0, 0.125) * 2**96

        // Finalization, we need to:
        // * multiply by the scale factor s = 5.549…
        // * add ln(2**96 / 10**18)
        // * add k * ln(2)
        // * multiply by 10**18 / 2**96 = 5**18 >> 78

        // mul s * 5e18 * 2**96, base is now 5**18 * 2**192
        r = r.wrapping_mul(int256!(1677202110996718588342820967067443963516166));
        // add ln(2) * k * 5e18 * 2**192
        r = r.wrapping_add(
            int256!(16597577552685614221487285958193947469193820559219878177908093499208371)
                .wrapping_mul(k),
        );
        // add ln(2**96 / 10**18) * 5e18 * 2**192
        r = r.wrapping_add(int256!(
            600920179829731861736702779321621459595472258049074101567377883020018308
        ));
        // base conversion: mul 2**18 / 2**192
        r = r.asr(174);

        r
    }
}

impl Distribution<FixedPoint> for Standard {
    fn sample<R: Rng + ?Sized>(&self, rng: &mut R) -> FixedPoint {
        FixedPoint(U256::from(rng.gen::<[u8; 32]>()))
    }
}

pub struct UniformFixedPoint {
    low: FixedPoint,
    high: FixedPoint,
}

impl SampleUniform for FixedPoint {
    type Sampler = UniformFixedPoint;
}

impl UniformSampler for UniformFixedPoint {
    type X = FixedPoint;

    #[inline]
    fn new<B1, B2>(low_b: B1, high_b: B2) -> Self
    where
        B1: SampleBorrow<Self::X> + Sized,
        B2: SampleBorrow<Self::X> + Sized,
    {
        let low = *low_b.borrow();
        let high = *high_b.borrow();
        if low >= high {
            panic!("UniformFixedPoint::new called with invalid range");
        }
        UniformFixedPoint { low, high }
    }

    #[inline]
    fn new_inclusive<B1, B2>(low_b: B1, high_b: B2) -> Self
    where
        B1: SampleBorrow<Self::X> + Sized,
        B2: SampleBorrow<Self::X> + Sized,
    {
        let low = *low_b.borrow();
        let high = *high_b.borrow();
        if low > high {
            panic!("UniformFixedPoint::new called with invalid range");
        }
        UniformFixedPoint::new(low, high + FixedPoint::from(1))
    }

    #[inline]
    fn sample<R: Rng + ?Sized>(&self, rng: &mut R) -> FixedPoint {
        let value = rng.gen::<FixedPoint>();
        let size: FixedPoint = self.high - self.low;
        let narrowed = FixedPoint::from(value.0 % size.0);
        narrowed + self.low
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
    use hyperdrive_wrappers::wrappers::mock_fixed_point_math::MockFixedPointMath;
    use rand::{thread_rng, Rng};
    use std::{convert::TryFrom, panic, sync::Arc, time::Duration};

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
            let actual = panic::catch_unwind(|| a + b);
            match runner.mock.add(a.into(), b.into()).call().await {
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected)),
                Err(_) => assert!(actual.is_err()),
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
            let actual = panic::catch_unwind(|| a - b);
            match runner.mock.sub(a.into(), b.into()).call().await {
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected)),
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }

    #[test]
    fn test_mul_div_down_failure() {
        // Ensure that division by zero fails.
        assert!(panic::catch_unwind(|| fixed!(1e18).mul_div_down(fixed!(1e18), 0.into())).is_err());
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
            let actual = panic::catch_unwind(|| a.mul_div_down(b, c));
            match runner
                .mock
                .mul_div_down(a.into(), b.into(), c.into())
                .call()
                .await
            {
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected)),
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }

    #[test]
    fn test_mul_div_up_failure() {
        // Ensure that division by zero fails.
        assert!(panic::catch_unwind(|| fixed!(1e18).mul_div_up(fixed!(1e18), 0.into())).is_err());
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
            let actual = panic::catch_unwind(|| a.mul_div_up(b, c));
            match runner
                .mock
                .mul_div_up(a.into(), b.into(), c.into())
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
    async fn fuzz_mul_down() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let a: FixedPoint = rng.gen();
            let b: FixedPoint = rng.gen();
            let actual = panic::catch_unwind(|| a * b);
            match runner.mock.mul_down(a.into(), b.into()).call().await {
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected)),
                Err(_) => assert!(actual.is_err()),
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
            let actual = panic::catch_unwind(|| a.mul_up(b));
            match runner.mock.mul_up(a.into(), b.into()).call().await {
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected)),
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }

    #[test]
    fn test_div_down_failure() {
        // Ensure that division by zero fails.
        assert!(panic::catch_unwind(|| fixed!(1e18) / fixed!(0)).is_err());
    }

    #[tokio::test]
    async fn fuzz_div_down() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let a: FixedPoint = rng.gen();
            let b: FixedPoint = rng.gen();
            let actual = panic::catch_unwind(|| a / b);
            match runner.mock.div_down(a.into(), b.into()).call().await {
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected)),
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }

    #[test]
    fn test_div_up_failure() {
        // Ensure that division by zero fails.
        assert!(panic::catch_unwind(|| fixed!(1e18).div_up(0.into())).is_err());
    }

    #[tokio::test]
    async fn fuzz_div_up() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let a: FixedPoint = rng.gen();
            let b: FixedPoint = rng.gen();
            let actual = panic::catch_unwind(|| a.div_up(b));
            match runner.mock.div_up(a.into(), b.into()).call().await {
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected)),
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_pow_narrow() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let x: FixedPoint = rng.gen_range(fixed!(0)..=fixed!(1e18));
            let y: FixedPoint = rng.gen_range(fixed!(0)..=fixed!(1e18));
            let actual = panic::catch_unwind(|| x.pow(y));
            match runner.mock.pow(x.into(), y.into()).call().await {
                Ok(expected) => {
                    assert_eq!(actual.unwrap(), FixedPoint::from(expected));
                }
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_pow() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let x: FixedPoint = rng.gen();
            let y: FixedPoint = rng.gen();
            let actual = panic::catch_unwind(|| x.pow(y));
            match runner.mock.pow(x.into(), y.into()).call().await {
                Ok(expected) => assert_eq!(actual.unwrap(), FixedPoint::from(expected)),
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_exp_narrow() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let x: I256 = rng.gen_range(fixed!(0)..=fixed!(1e18)).into();
            let actual = panic::catch_unwind(|| FixedPoint::ln(x));
            match runner.mock.ln(x).call().await {
                Ok(expected) => assert_eq!(actual.unwrap(), expected),
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_exp() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let x: I256 = rng.gen::<FixedPoint>().into();
            let actual = panic::catch_unwind(|| FixedPoint::exp(x));
            match runner.mock.exp(x).call().await {
                Ok(expected) => assert_eq!(actual.unwrap(), expected),
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }

    #[tokio::test]
    async fn fuzz_ln_narrow() -> Result<()> {
        let runner = setup().await?;

        // Fuzz the rust and solidity implementations against each other.
        let mut rng = thread_rng();
        for _ in 0..FUZZ_RUNS {
            let x: I256 = rng.gen_range(fixed!(0)..=fixed!(1e18)).into();
            let actual = panic::catch_unwind(|| FixedPoint::ln(x));
            match runner.mock.ln(x).call().await {
                Ok(expected) => assert_eq!(actual.unwrap(), expected),
                Err(_) => assert!(actual.is_err()),
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
            let x: I256 = rng.gen::<FixedPoint>().into();
            let actual = panic::catch_unwind(|| FixedPoint::ln(x));
            match runner.mock.ln(x).call().await {
                Ok(expected) => assert_eq!(actual.unwrap(), expected),
                Err(_) => assert!(actual.is_err()),
            }
        }

        Ok(())
    }
}
