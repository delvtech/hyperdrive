use ethers::{signers::LocalWallet, types::Address};
use eyre::Result;
use hyperdrive_wrappers::wrappers::{
    erc4626_hyperdrive_deployer_coordinator::ERC4626HyperdriveDeployerCoordinator,
    hyperdrive_factory::HyperdriveFactory,
    steth_hyperdrive_deployer_coordinator::StETHHyperdriveDeployerCoordinator,
};
use test_utils::chain::Chain;

#[tokio::main]
async fn main() -> Result<()> {
    let chain = Chain::connect(Some(std::env::var("HYPERDRIVE_ETHEREUM_URL")?), None).await?;
    let signer = std::env::var("PRIVATE_KEY")?.parse::<LocalWallet>()?;
    let client = chain.client(signer).await?;

    // Get an instance of the deployer coordinator.
    let coordinator = StETHHyperdriveDeployerCoordinator::new(
        "0x6aa9615F0dF3F3891e8d2723A6b2A7973b5da299".parse::<Address>()?,
        client.clone(),
    );

    println!(
        "steth core deployer {:?}",
        coordinator.core_deployer().call().await?,
    );
    println!(
        "steth target0 {:?}",
        coordinator.target_0_deployer().call().await?,
    );
    println!(
        "steth target1 {:?}",
        coordinator.target_1_deployer().call().await?,
    );
    println!(
        "steth target2 {:?}",
        coordinator.target_2_deployer().call().await?,
    );
    println!(
        "steth target3 {:?}",
        coordinator.target_3_deployer().call().await?,
    );
    println!(
        "steth target4 {:?}",
        coordinator.target_4_deployer().call().await?,
    );

    // Get an instance of the deployer coordinator.
    let coordinator = ERC4626HyperdriveDeployerCoordinator::new(
        "0x28273c4E6c69317626E14AF3020e063ab215e2b4".parse::<Address>()?,
        client.clone(),
    );

    println!(
        "erc4626 core deployer {:?}",
        coordinator.core_deployer().call().await?,
    );
    println!(
        "erc4626 target0 {:?}",
        coordinator.target_0_deployer().call().await?,
    );
    println!(
        "erc4626 target1 {:?}",
        coordinator.target_1_deployer().call().await?,
    );
    println!(
        "erc4626 target2 {:?}",
        coordinator.target_2_deployer().call().await?,
    );
    println!(
        "erc4626 target3 {:?}",
        coordinator.target_3_deployer().call().await?,
    );
    println!(
        "erc4626 target4 {:?}",
        coordinator.target_4_deployer().call().await?,
    );

    Ok(())
}
