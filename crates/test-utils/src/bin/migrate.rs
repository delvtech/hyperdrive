use std::fs::{create_dir_all, File};

use eyre::Result;
use test_utils::chain::{Chain, TestChain};

#[tokio::main]
async fn main() -> Result<()> {
    // Spin up a new test chain. This will read from the environment to get the
    // Ethereum RPC URL, the Ethereum private key that specifies the deployer's
    // account, and the configurations for the test chain.
    let chain = TestChain::new_with_factory(1).await?;

    // Write the chain's addresses to a file.
    create_dir_all("./artifacts")?;
    let f = File::create("./artifacts/addresses.json")?;
    serde_json::to_writer(f, &chain.addresses())?;

    Ok(())
}
