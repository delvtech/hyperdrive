use eyre::Result;
use test_utils::{
    agent::Agent,
    chain::{Chain, TestChain},
};

#[tokio::main]
async fn main() -> Result<()> {
    // Load a test chain from the example crash report.
    let chain = TestChain::load_crash("examples/crash_report.json").await?;

    // Create an agent to interact with the chain.
    let alice = chain.accounts()[0].clone();
    let alice = Agent::new(chain.client(alice).await?, chain.addresses(), None).await?;

    // Log the pool config and info.
    println!("pool state = {:#?}", alice.get_state().await?);

    // This will fail because the chain is in a crashed state.
    //
    // To figure out why the chain crashed, add logs in the Hyperdrive contract,
    // uncomment the next line, and then re-run the example with the
    // `HYPERDRIVE_ETHEREUM_URL` set to the URL of your local Ethereum node.
    // chain.reproduce_crash().await?;

    Ok(())
}
