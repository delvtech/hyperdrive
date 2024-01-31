use std::{
    env,
    fs::{create_dir_all, File},
};

use ethers::{signers::LocalWallet, types::Bytes, utils::hex::FromHex};
use eyre::Result;
use test_utils::chain::{Chain, TestChain};

#[tokio::main]
async fn main() -> Result<()> {
    // Load the private key from the environment and create a local signer.

    let signer = LocalWallet::from_bytes(&Bytes::from_hex(env::var("PRIVATE_KEY")?)?)?;

    // Spin up a new test chain. This will read from the environment to get the
    // Ethereum RPC URL, the Ethereum private key that specifies the deployer's
    // account, and the configurations for the test chain.
    let chain = TestChain::new_with_accounts(vec![signer]).await?;

    // Write the chain's addresses to a file.
    create_dir_all("./artifacts")?;
    let mut f = File::create("./artifacts/addresses.json")?;
    serde_json::to_writer(f, &chain.addresses())?;

    Ok(())
}
