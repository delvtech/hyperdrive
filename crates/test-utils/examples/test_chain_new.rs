use eyre::Result;
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;
use test_utils::{
    agent::Agent,
    chain::{Chain, TestChain},
};

#[tokio::main]
async fn main() -> Result<()> {
    // Spin up a new test chain.
    let chain = TestChain::new(
        1, // the number of accounts to fund
    )
    .await?;

    // Create an agent to interact with the chain.
    let alice = chain.accounts()[0].clone();
    let mut alice = Agent::new(chain.client(alice).await?, chain.addresses(), None).await?;

    // Initialize the pool. In order for Alice to initialize the pool, she'll
    // need to mint base tokens and approve the Hyperdrive pool. We can
    // accomplish this by calling the `fund` method on the agent.
    let rate = fixed!(0.05e18);
    let contribution = fixed!(500_000_000e18);
    alice.fund(contribution).await?;
    alice.initialize(rate, contribution, None).await?;

    // Log the pool config and info.
    println!("pool state = {:#?}", alice.get_state().await?);

    Ok(())
}
