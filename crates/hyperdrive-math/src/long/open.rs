use ethers::types::I256;
use fixed_point::FixedPoint;

use crate::{
    get_effective_share_reserves, get_max_spot_price, open_long_curve_fees,
    yield_space::{calculate_bonds_out_given_shares_in_down, get_spot_price},
    State, YieldSpace,
};
/// Gets the long amount that will be opened for a given base amount.
///
/// The long amount $y(x)$ that a trader will receive is given by:
///
/// $$
/// y(x) = y_{*}(x) - c(x)
/// $$
///
/// Where $y_{*}(x)$ is the amount of long that would be opened if there was
/// no curve fee and [$c(x)$](long_curve_fee) is the curve fee. $y_{*}(x)$
/// is given by:
///
/// $$
/// y_{*}(x) = y - \left(
///                k - \tfrac{c}{\mu} \cdot \left(
///                    \mu \cdot \left( z + \tfrac{x}{c}
///                \right) \right)^{1 - t_s}
///            \right)^{\tfrac{1}{1 - t_s}}
/// $$
pub fn calculate_open_long<F: Into<FixedPoint>>(
    share_adjustment: I256,
    effective_share_reserves: FixedPoint,
    share_reserves: FixedPoint,
    bond_reserves: FixedPoint,
    share_price: FixedPoint,
    initial_share_price: FixedPoint,
    time_parameter: FixedPoint,
    flat_fee: FixedPoint,
    curve_fee: FixedPoint,
    base_amount: F,
) -> FixedPoint {
    let base_amount = base_amount.into();
    let long_amount = calculate_bonds_out_given_shares_in_down(
        effective_share_reserves,
        bond_reserves,
        share_price,
        initial_share_price,
        time_parameter,
        base_amount / share_price,
    );

    // Throw an error if opening the long would result in negative interest.
    let ending_spot_price = spot_price_after_long(
        share_adjustment,
        share_reserves,
        bond_reserves,
        share_price,
        initial_share_price,
        time_parameter,
        base_amount,
        long_amount,
    );
    let max_spot_price = get_max_spot_price(
        effective_share_reserves,
        bond_reserves,
        initial_share_price,
        time_parameter,
        flat_fee,
        curve_fee,
    );
    if ending_spot_price > max_spot_price {
        // TODO would be nice to return a `Result` here instead of a panic.
        panic!("InsufficientLiquidity: Negative Interest");
    }

    long_amount
        - open_long_curve_fees(
            effective_share_reserves,
            bond_reserves,
            initial_share_price,
            time_parameter,
            curve_fee,
            base_amount,
        )
}

fn spot_price_after_long(
    share_adjustment: I256,
    share_reserves: FixedPoint,
    bond_reserves: FixedPoint,
    share_price: FixedPoint,
    initial_share_price: FixedPoint,
    time_parameter: FixedPoint,
    base_amount: FixedPoint,
    bond_amount: FixedPoint,
) -> FixedPoint {
    get_spot_price(
        get_effective_share_reserves(share_reserves + base_amount / share_price, share_adjustment),
        bond_reserves - bond_amount,
        initial_share_price,
        time_parameter,
    )
}

impl State {
    /// Gets the long amount that will be opened for a given base amount.
    ///
    /// The long amount $y(x)$ that a trader will receive is given by:
    ///
    /// $$
    /// y(x) = y_{*}(x) - c(x)
    /// $$
    ///
    /// Where $y_{*}(x)$ is the amount of long that would be opened if there was
    /// no curve fee and [$c(x)$](long_curve_fee) is the curve fee. $y_{*}(x)$
    /// is given by:
    ///
    /// $$
    /// y_{*}(x) = y - \left(
    ///                k - \tfrac{c}{\mu} \cdot \left(
    ///                    \mu \cdot \left( z + \tfrac{x}{c}
    ///                \right) \right)^{1 - t_s}
    ///            \right)^{\tfrac{1}{1 - t_s}}
    /// $$
    pub fn calculate_open_long<F: Into<FixedPoint>>(&self, base_amount: F) -> FixedPoint {
        calculate_open_long(
            self.zeta(),
            self.ze(),
            self.z(),
            self.y(),
            self.c(),
            self.mu(),
            self.t(),
            self.flat_fee(),
            self.curve_fee(),
            base_amount,
        )
    }

    #[deprecated(since = "0.4.0", note = "please use `calculate_open_long` instead")]
    pub fn get_long_amount<F: Into<FixedPoint>>(&self, base_amount: F) -> FixedPoint {
        self.calculate_open_long(base_amount)
    }

    /// Gets the spot price after opening a Hyperdrive long.
    pub fn get_spot_price_after_long(&self, base_amount: FixedPoint) -> FixedPoint {
        let bond_amount = self.calculate_open_long(base_amount);
        self.spot_price_after_long(base_amount, bond_amount)
    }

    fn spot_price_after_long(
        &self,
        base_amount: FixedPoint,
        bond_amount: FixedPoint,
    ) -> FixedPoint {
        spot_price_after_long(
            self.zeta(),
            self.z(),
            self.y(),
            self.c(),
            self.mu(),
            self.t(),
            base_amount,
            bond_amount,
        )
    }
}

#[cfg(test)]
mod tests {
    use eyre::Result;
    use fixed_point_macros::fixed;
    use rand::{thread_rng, Rng};
    use test_utils::{
        agent::Agent,
        chain::{Chain, TestChain},
        constants::FUZZ_RUNS,
    };

    use super::*;

    #[tokio::test]
    async fn fuzz_get_spot_price_after_long() -> Result<()> {
        // Spawn a test chain and create two agents -- Alice and Bob. Alice
        // is funded with a large amount of capital so that she can initialize
        // the pool. Bob is funded with a small amount of capital so that we
        // can test opening a long and verify that the ending spot price is what
        // we expect.
        let mut rng = thread_rng();
        let chain = TestChain::new(2).await?;
        let (alice, bob) = (chain.accounts()[0].clone(), chain.accounts()[1].clone());
        let mut alice =
            Agent::new(chain.client(alice).await?, chain.addresses().clone(), None).await?;
        let mut bob = Agent::new(chain.client(bob).await?, chain.addresses(), None).await?;

        for _ in 0..*FUZZ_RUNS {
            // Snapshot the chain.
            let id = chain.snapshot().await?;

            // Fund Alice and Bob.
            let fixed_rate = rng.gen_range(fixed!(0.01e18)..=fixed!(0.1e18));
            let contribution = rng.gen_range(fixed!(10_000e18)..=fixed!(500_000_000e18));
            let budget = rng.gen_range(fixed!(10e18)..=fixed!(500_000_000e18));
            alice.fund(contribution).await?;
            bob.fund(budget).await?;

            // Alice initializes the pool.
            alice.initialize(fixed_rate, contribution, None).await?;

            // Attempt to predict the spot price after opening a long.
            let base_paid = rng.gen_range(fixed!(0.1e18)..=bob.get_max_long(None).await?);
            let expected_spot_price = bob.get_state().await?.get_spot_price_after_long(base_paid);

            // Open the long.
            bob.open_long(base_paid, None, None).await?;

            // Verify that the predicted spot price is equal to the ending spot
            // price. These won't be exactly equal because the vault share price
            // increases between the prediction and opening the long.
            let actual_spot_price = bob.get_state().await?.get_spot_price();
            let delta = if actual_spot_price > expected_spot_price {
                actual_spot_price - expected_spot_price
            } else {
                expected_spot_price - actual_spot_price
            };
            let tolerance = fixed!(1e9);
            assert!(
                delta < tolerance,
                "expected: delta = {} < {} = tolerance",
                delta,
                tolerance
            );

            // Revert to the snapshot and reset the agent's wallets.
            chain.revert(id).await?;
            alice.reset(Default::default());
            bob.reset(Default::default());
        }

        Ok(())
    }
}
