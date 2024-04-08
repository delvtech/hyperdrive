use std::{
    env,
    fs::{create_dir_all, File},
};

use ethers::signers::LocalWallet;
use eyre::Result;
use test_utils::{
    chain::{Chain, TestChainConfig},
    constants::ALICE,
};

#[tokio::main]
async fn main() -> Result<()> {
    // Load the config from the environment.
    let config = envy::from_env::<TestChainConfig>()?;

    // Connect to the chain.
    let chain = Chain::connect(Some(env::var("HYPERDRIVE_ETHEREUM_URL")?), None).await?;
    let deployer = env::var("DEPLOYER_PRIVATE_KEY")?.parse::<LocalWallet>()?;

    // Deploy the factory.
    let addresses = chain.full_deploy(deployer, config).await?;

    // Write the chain's addresses to a file.
    create_dir_all("./artifacts")?;
    let f = File::create("./artifacts/addresses.json")?;
    serde_json::to_writer(f, &addresses)?;

    Ok(())
}
