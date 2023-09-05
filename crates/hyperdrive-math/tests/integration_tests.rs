use ethers::types::U256;
use eyre::Result;
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, uint256};
use hyperdrive_wrappers::wrappers::i_hyperdrive::Checkpoint;
use rand::{rngs::ThreadRng, thread_rng, Rng};
use rand_chacha::ChaCha8Rng;
use test_utils::{
    agent::Agent,
    chain::{Chain, ChainClient, TestChain},
    constants::FUZZ_RUNS,
};

/// Executes random trades throughout a Hyperdrive term.
async fn preamble(
    rng: &mut ThreadRng,
    alice: &mut Agent<ChainClient, ChaCha8Rng>,
    bob: &mut Agent<ChainClient, ChaCha8Rng>,
    celine: &mut Agent<ChainClient, ChaCha8Rng>,
    fixed_rate: FixedPoint,
) -> Result<()> {
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
    alice.initialize(fixed_rate, alice.base()).await?;

    // Advance the time for over a term and make trades in some of the checkpoints.
    let mut time_remaining = alice.get_config().position_duration;
    while time_remaining > uint256!(0) {
        // Bob opens a long.
        let discount = rng.gen_range(fixed!(0.1e18)..=fixed!(0.5e18));
        let long_amount = rng.gen_range(fixed!(1e12)..=bob.get_max_long(None).await? * discount);
        bob.open_long(long_amount, None).await?;

        // Celine opens a short.
        let discount = rng.gen_range(fixed!(0.1e18)..=fixed!(0.5e18));
        let short_amount =
            rng.gen_range(fixed!(1e12)..=celine.get_max_short(None).await? * discount);
        celine.open_short(short_amount, None).await?;

        // Advance a checkpoint.
        let multiplier = rng.gen_range(fixed!(0.5e18)..=fixed!(10e18));
        let delta = FixedPoint::from(time_remaining)
            .min(FixedPoint::from(alice.get_config().checkpoint_duration) * multiplier);
        time_remaining -= U256::from(delta);
        alice
            .advance_time_with_checkpoints(
                fixed!(0), // FIXME: Use a real rate.
                delta,
            )
            .await?;
    }

    Ok(())
}

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

        // Run the preamble.
        let fixed_rate = fixed!(0.05e18);
        preamble(&mut rng, &mut alice, &mut bob, &mut celine, fixed_rate).await?;

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
            // We currently allow up to a tolerance of 0.2%, which means
            // that the max short is always consuming at least 99.8% of
            // the budget.
            let error_tolerance = fixed!(0.002e18);
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

        // Run the preamble.
        let fixed_rate = fixed!(0.05e18);
        preamble(&mut rng, &mut alice, &mut bob, &mut celine, fixed_rate).await?;

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
