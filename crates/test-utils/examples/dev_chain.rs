use eyre::Result;
use test_utils::{
    agent::Agent,
    chain::{Chain, DevChain, MNEMONIC},
};

/// To run this example, spin up a local compose app running on port 8545.
#[tokio::main]
async fn main() -> Result<()> {
    // Connect to an instance of Hyperdrive on a local compose app.
    let chain = DevChain::new(
        "http://localhost:8545", // the ethereum URL
        "http://localhost:8080", // the artifacts server's URL
        MNEMONIC,                // the mnemonic to use when generating accounts
        1,                       // the number of accounts to fund
    )
    .await?;

    // Create an agent to interact with the chain.
    let alice = chain.accounts()[0].clone();
    let agent = Agent::new(chain.client(alice).await?, chain.addresses(), None).await?;

    // Log the pool config and info.
    println!("pool state = {:#?}", agent.get_state().await?);

    Ok(())
}
