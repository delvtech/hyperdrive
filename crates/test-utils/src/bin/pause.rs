use std::env;

use dotenvy::dotenv;
use ethers::signers::LocalWallet;
use eyre::Result;
use hyperdrive_wrappers::wrappers::ihyperdrive::IHyperdrive;
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
    println!("Pausing the pool...");
    let hyperdrive = IHyperdrive::new(chain.addresses().erc4626_hyperdrive, client);
    hyperdrive.pause(true).send().await?.await?;

    // Check that the pool is paused.
    let market_state = hyperdrive.get_market_state().call().await?;
    if market_state.is_paused {
        println!("The pool was successfully paused!");
    } else {
        panic!("The pool was not paused!");
    }

    Ok(())
}
