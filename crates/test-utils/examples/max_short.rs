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
        2, // we're funding 2 accounts
    )
    .await?;

    // Create an agent to interact with the chain.
    let (alice, bob) = (chain.accounts()[0].clone(), chain.accounts()[1].clone());
    let mut alice = Agent::new(chain.client(alice).await?, chain.addresses(), None).await?;
    let mut bob = Agent::new(chain.client(bob).await?, chain.addresses(), None).await?;

    // Initialize the pool. In order for Alice to initialize the pool, she'll
    // need to mint base tokens and approve the Hyperdrive pool. We can
    // accomplish this by calling the `fund` method on the agent.
    let rate = fixed!(0.05e18);
    let contribution = fixed!(500_000_000e18);
    alice.fund(contribution).await?;
    alice.initialize(rate, contribution, None).await?;

    // Bob checks to see how large his max short is and logs it.
    let budget = fixed!(10_000_000e18);
    bob.fund(budget).await?;
    println!("Bob's budget is {}.", budget);
    let max_short = bob.get_max_short(None).await?;
    println!(
        "Bob's max short is {}. The starting spot price is {}",
        max_short,
        bob.get_state().await?.get_spot_price()
    );

    // Bob opens a max short position.
    bob.open_short(max_short, None, None).await?;
    println!(
        "Bob successfully opened the short! The ending spot price is {}",
        bob.get_state().await?.get_spot_price()
    );

    Ok(())
}
