use ethers::{providers::Middleware, types::Address};
use eyre::Result;
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, uint256};
use hyperdrive_addresses::Addresses;
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
    let chain = TestChain::new(2).await?;
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

#[ignore]
#[tokio::test]
async fn test_repro() -> Result<()> {
    // TODO: Role this up into `TestChain` so that we parse the crash report
    // into a reproduction environment.
    //
    // Set up the chain and agents. We load the state dump from a dump file.
    let state_dump = std::fs::read_to_string("./state_dump.json")?;
    let chain = TestChain::load(
        &state_dump.trim(),
        Addresses {
            base: "0x5FbDB2315678afecb367f032d93F642f64180aa3".parse::<Address>()?,
            hyperdrive: "0x3B02fF1e626Ed7a8fd6eC5299e2C54e1421B626B".parse::<Address>()?,
        },
        1,
    )
    .await?;
    let mut alice = Agent::new(
        chain.client(chain.accounts()[0].clone()).await?,
        chain.addresses().clone(),
        None,
    )
    .await?;
    let block_timestamp = {
        let block_number = chain.provider().get_block_number().await?;
        chain
            .provider()
            .get_block(block_number)
            .await?
            .unwrap()
            .timestamp
    };
    // HACK(jalextowle): For some reason `increaseTime` is consistently off by 4.
    chain
        .increase_time(1697973315 - block_timestamp.low_u64() + 4)
        .await?;

    // Attempt to reproduce the crash.
    alice
        .open_short(fixed!(8.753861575436865432e18), None)
        .await?;

    Ok(())
}
