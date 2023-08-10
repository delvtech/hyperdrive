use eyre::Result;
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;
use test_utils::agent::Agent;
use test_utils::test_chain::TestChain;

#[tokio::test]
async fn test_simple() -> Result<()> {
    let chain = TestChain::new().await?;
    let mut alice = Agent::new(
        chain.accounts()[0].clone(),
        chain.provider.clone(),
        chain.addresses.clone(),
    )
    .await?;
    let mut bob = Agent::new(
        chain.accounts()[1].clone(),
        chain.provider.clone(),
        chain.addresses,
    )
    .await?;

    // Fund Alice and Bob's accounts.
    let contribution = fixed!(500_000_000e18);
    alice.fund(contribution).await?;
    bob.fund(fixed!(100_000_000_000e18)).await?;

    // Initialize the pool.
    let rate = fixed!(0.05e18);
    alice.initialize(rate, contribution).await?;

    // Bob performs 20 random actions.
    for _ in 0..20 {
        // FIXME: We need to check invariants
        bob.act().await?;
    }

    Ok(())
}
