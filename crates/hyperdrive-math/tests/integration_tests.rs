// TODO: This testing should be improved in several different ways:
//
// 1. [ ] Test with intra-checkpoint netting. We should make some trades
//        and then advance through checkpoints. This will make it possible
//        for some positive checkpoint exposure to accumulate.
// 2. [ ] Test with with matured positions updating zeta.

use ethers::types::U256;
use eyre::Result;
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;
use hyperdrive_wrappers::wrappers::i_hyperdrive::Checkpoint;
use rand::{thread_rng, Rng};
use test_utils::{
    agent::Agent,
    chain::{Chain, TestChain},
    constants::FUZZ_RUNS,
};

// FIXME: This test requires too large of a tolerance. It's probably time to
//        write this test for real.
#[tokio::test]
pub async fn test_integration_get_max_short() -> Result<()> {
    let mut rng = thread_rng();
    let chain = TestChain::new(3).await?;
    let mut alice = Agent::new(
        chain.client(chain.accounts()[0].clone()).await?,
        chain.addresses(),
        None,
    )
    .await?;
    let mut bob = Agent::new(
        chain.client(chain.accounts()[1].clone()).await?,
        chain.addresses(),
        None,
    )
    .await?;
    let mut celine = Agent::new(
        chain.client(chain.accounts()[2].clone()).await?,
        chain.addresses(),
        None,
    )
    .await?;

    for _ in 0..*FUZZ_RUNS {
        // Snapshot the chain.
        let id = chain.snapshot().await?;

        // Fund the agent accounts and initialize the pool.
        alice
            .fund(rng.gen_range(fixed!(1_000e18)..=fixed!(500_000_000e18)))
            .await?;
        bob.fund(rng.gen_range(fixed!(1_000e18)..=fixed!(500_000_000e18)))
            .await?;
        celine
            .fund(rng.gen_range(fixed!(1_000e18)..=fixed!(500_000_000e18)))
            .await?;

        // Alice initializes the pool.
        let fixed_rate = fixed!(0.05e18);
        alice.initialize(fixed_rate, alice.base()).await?;

        // Bob opens a long.
        let long_amount = rng.gen_range(fixed!(1e12)..=bob.get_max_long(None).await?);
        bob.open_long(long_amount, None).await?;

        // Celine opens a short.
        let short_amount = rng.gen_range(fixed!(1e12)..=celine.get_max_short(None).await?);
        celine.open_short(short_amount, None).await?;

        // Celine opens a max short. Despite the trading that happened before this,
        // we expect Celine to open the max short on the pool or consume almost all
        // of her budget.
        let state = alice.get_state().await?;
        let Checkpoint {
            share_price: open_share_price,
            ..
        } = alice
            .get_checkpoint(state.to_checkpoint(alice.now().await?))
            .await?;
        let global_max_short = state.get_max_short(U256::MAX, open_share_price, None, None);
        let budget = bob.base();
        let slippage_tolerance = fixed!(0.001e18);
        let max_short = bob.get_max_short(Some(slippage_tolerance)).await?;
        bob.open_short(max_short, None).await?;

        if max_short != global_max_short {
            // We currently allow up to a tolerance of 0.1%, which means
            // that the max short is always consuming at least 99.9% of
            // the budget.
            let error_tolerance = fixed!(0.001e18);
            assert!(
                bob.base() < budget * (fixed!(1e18) - slippage_tolerance) * error_tolerance,
                "expected (base={}) < (budget={}) * {} = {}",
                bob.base(),
                budget,
                error_tolerance,
                budget * error_tolerance
            );
        }

        // Revert to the snapshot and reset the agent's wallets.
        chain.revert(id).await?;
        alice.reset(Default::default());
        bob.reset(Default::default());
        celine.reset(Default::default());
    }

    Ok(())
}

#[tokio::test]
pub async fn test_integration_get_max_long() -> Result<()> {
    let mut rng = thread_rng();
    let chain = TestChain::new(3).await?;
    let mut alice = Agent::new(
        chain.client(chain.accounts()[0].clone()).await?,
        chain.addresses(),
        None,
    )
    .await?;
    let mut bob = Agent::new(
        chain.client(chain.accounts()[1].clone()).await?,
        chain.addresses(),
        None,
    )
    .await?;
    let mut celine = Agent::new(
        chain.client(chain.accounts()[2].clone()).await?,
        chain.addresses(),
        None,
    )
    .await?;

    for _ in 0..*FUZZ_RUNS {
        // Snapshot the chain.
        let id = chain.snapshot().await?;

        // Fund the agent accounts and initialize the pool.
        alice
            .fund(rng.gen_range(fixed!(1_000e18)..=fixed!(500_000_000e18)))
            .await?;
        bob.fund(rng.gen_range(fixed!(1_000e18)..=fixed!(500_000_000e18)))
            .await?;
        celine
            .fund(rng.gen_range(fixed!(1_000e18)..=fixed!(500_000_000e18)))
            .await?;
        let fixed_rate = fixed!(0.05e18);
        alice.initialize(fixed_rate, alice.base()).await?;

        // Bob opens a long.
        let long_amount = rng.gen_range(fixed!(1e12)..=bob.get_max_long(None).await?);
        bob.open_long(long_amount, None).await?;

        // Celine opens a short.
        let short_amount = rng.gen_range(fixed!(1e12)..=celine.get_max_short(None).await?);
        celine.open_short(short_amount, None).await?;

        // Bob opens a max long. Despite the trading that happened before this,
        // we expect Bob's max long to bring the spot price close to 1, exhaust the
        // pool's solvency, or exhaust Bob's budget.
        let max_long = bob.get_max_long(None).await?;
        bob.open_long(max_long, None).await?;
        let is_max_price = {
            let state = bob.get_state().await?;
            fixed!(1e18) - state.get_spot_price() < fixed!(1e15)
        };
        let is_solvency_consumed = {
            let state = bob.get_state().await?;
            let error_tolerance = fixed!(1_000e18).mul_div_down(fixed_rate, fixed!(0.1e18));
            state.get_solvency() < error_tolerance
        };
        let is_budget_consumed = {
            let error_tolerance = fixed!(1e18);
            bob.base() < error_tolerance
        };
        assert!(
            is_max_price || is_solvency_consumed || is_budget_consumed,
            "Invalid max long."
        );

        // Revert to the snapshot and reset the agent's wallets.
        chain.revert(id).await?;
        alice.reset(Default::default());
        bob.reset(Default::default());
        celine.reset(Default::default());
    }

    Ok(())
}
