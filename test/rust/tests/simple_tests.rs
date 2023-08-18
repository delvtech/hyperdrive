use eyre::Result;
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;
use test_utils::{
    agent::Agent,
    chain::{Chain, TestChain},
};

// TODO: We should be able to run this in CI.
#[ignore]
#[tokio::test]
async fn test_simple() -> Result<()> {
    // Set up the logger.
    tracing_subscriber::fmt::init();

    // Set up the chain and agents.
    let chain = TestChain::new(None, 2).await?;
    let (alice, bob) = (chain.accounts()[0].clone(), chain.accounts()[1].clone());
    let mut alice = Agent::new(chain.client(alice).await?, chain.addresses().clone(), None).await?;
    let mut bob = Agent::new(chain.client(bob).await?, chain.addresses(), None).await?;

    // Fund Alice and Bob's accounts.
    let contribution = fixed!(500_000_000e18);
    alice.fund(contribution).await?;
    bob.fund(fixed!(500_000_000e18)).await?;

    // Initialize the pool.
    let rate = fixed!(0.05e18);
    alice.initialize(rate, contribution).await?;

    // Bob performs 20 random actions.
    for _ in 0..20 {
        bob.act().await?;
    }

    Ok(())
}
