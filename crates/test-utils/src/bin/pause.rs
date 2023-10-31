use std::env;

use dotenvy::dotenv;
use ethers::signers::LocalWallet;
use eyre::Result;
use hyperdrive_wrappers::wrappers::ierc4626_hyperdrive::IERC4626Hyperdrive;
use test_utils::chain::{Chain, DevChain, MNEMONIC};

#[tokio::main]
async fn main() -> Result<()> {
    // Connect to the chain and set up an agent with the provided envvars.
    dotenv().expect("Failed to load .env file");
    let chain = DevChain::new(
        &env::var("HYPERDRIVE_ETHEREUM_URL")?,
        &env::var("HYPERDRIVE_ARTIFACTS_URL")?,
        MNEMONIC,
        0,
    )
    .await?;
    let client = chain
        .client(env::var("HYPERDRIVE_PRIVATE_KEY")?.parse::<LocalWallet>()?)
        .await?;

    // Pause the pool.
    let hyperdrive = IERC4626Hyperdrive::new(chain.addresses().hyperdrive, client);
    hyperdrive.pause(true).send().await?.await?;

    Ok(())
}
