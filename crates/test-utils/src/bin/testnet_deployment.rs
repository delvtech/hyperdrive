/// This script deploys the contracts needed to run the Hyperdrive testnet on
/// Sepolia. This script will deploy the following contracts:
///
/// - HyperdriveFactory
/// - ERC4626HyperdriveDeployerCoordinator
/// - ERC4626HyperdriveCoreDeployer
/// - ERC4626HyperdriveTarget0Deployer
/// - ERC4626HyperdriveTarget1Deployer
/// - ERC4626HyperdriveTarget2Deployer
/// - ERC4626HyperdriveTarget3Deployer
/// - ERC4626HyperdriveTarget4Deployer
/// - StETHHyperdriveDeployerCoordinator
/// - StETHHyperdriveCoreDeployer
/// - StETHHyperdriveTarget0Deployer
/// - StETHHyperdriveTarget1Deployer
/// - StETHHyperdriveTarget2Deployer
/// - StETHHyperdriveTarget3Deployer
/// - StETHHyperdriveTarget4Deployer
/// - MockERC4626
/// - MockLido
///
/// After deploying these contracts and setting up the deployer coordinators,
/// this script will transfer ownership of the factory to a specified address.
use std::fs::{create_dir_all, File};
use std::{env, sync::Arc};

use ethers::{
    core::utils::keccak256,
    middleware::Middleware,
    signers::{LocalWallet, Signer},
    types::{Address, U256},
};
use eyre::Result;
use fixed_point_macros::uint256;
use hyperdrive_wrappers::wrappers::{
    erc20_forwarder_factory::ERC20ForwarderFactory, erc20_mintable::ERC20Mintable,
    erc4626_hyperdrive_core_deployer::ERC4626HyperdriveCoreDeployer,
    erc4626_hyperdrive_deployer_coordinator::ERC4626HyperdriveDeployerCoordinator,
    erc4626_target0_deployer::ERC4626Target0Deployer,
    erc4626_target1_deployer::ERC4626Target1Deployer,
    erc4626_target2_deployer::ERC4626Target2Deployer,
    erc4626_target3_deployer::ERC4626Target3Deployer,
    erc4626_target4_deployer::ERC4626Target4Deployer, hyperdrive_factory::HyperdriveFactory,
    hyperdrive_registry::HyperdriveRegistry, mock_erc4626::MockERC4626, mock_lido::MockLido,
    steth_hyperdrive_core_deployer::StETHHyperdriveCoreDeployer,
    steth_hyperdrive_deployer_coordinator::StETHHyperdriveDeployerCoordinator,
    steth_target0_deployer::StETHTarget0Deployer, steth_target1_deployer::StETHTarget1Deployer,
    steth_target2_deployer::StETHTarget2Deployer, steth_target3_deployer::StETHTarget3Deployer,
    steth_target4_deployer::StETHTarget4Deployer,
};
use test_utils::chain::{Chain, ChainClient};

#[tokio::main]
async fn main() -> Result<()> {
    // Load the environment variables.
    let ethereum_rpc_url = env::var("HYPERDRIVE_ETHEREUM_URL")?;
    let governance_address = env::var("GOVERNANCE_ADDRESS")?.parse::<Address>()?;
    let admin_address = env::var("ADMIN_ADDRESS")?.parse::<Address>()?;
    let deployer = env::var("DEPLOYER_PRIVATE_KEY")?.parse::<LocalWallet>()?;

    // Connect to the chain and get a client for the deployer.
    let chain = Chain::connect(Some(ethereum_rpc_url)).await?;
    let client = chain.client(deployer).await?;

    // Deploy the contracts.
    testnet_deployment(client, admin_address, governance_address).await?;

    Ok(())
}

async fn testnet_deployment(
    client: Arc<ChainClient<LocalWallet>>,
    admin_address: Address,
    governance_address: Address,
) -> Result<()> {
    // Deploy the DAI token and sDAI vault.
    let dai = ERC20Mintable::deploy(
        client.clone(),
        (
            "DAI".to_string(),
            "DAI".to_string(),
            uint256!(18),
            admin_address,
            true,
            uint256!(10_000e18),
        ),
    )?
    .send()
    .await?;
    let sdai = MockERC4626::deploy(
        client.clone(),
        (
            dai.address(),
            "Savings DAI".to_string(),
            "SDAI".to_string(),
            uint256!(0.13e18),
            admin_address,
            true,
            uint256!(10_000e18),
        ),
    )?
    .send()
    .await?;

    // Deploy the mock Lido system. We fund Lido with 0.001 eth to start to
    // avoid reverts when we initialize the pool.
    let lido = {
        let lido = MockLido::deploy(
            client.clone(),
            (uint256!(0.035e18), admin_address, true, uint256!(500e18)),
        )?
        .send()
        .await?;
        lido.submit(Address::zero())
            .value(uint256!(0.001e18))
            .send()
            .await?;
        lido
    };

    // Set minting as a public capability on all tokens and vaults and allow the
    // vault to burn tokens.
    dai.set_user_role(sdai.address(), 1, true).send().await?;
    dai.set_role_capability(
        1,
        keccak256("burn(uint256)".as_bytes())[0..4].try_into()?,
        true,
    )
    .send()
    .await?;
    dai.set_public_capability(
        keccak256("mint(uint256)".as_bytes())[0..4].try_into()?,
        true,
    )
    .send()
    .await?;
    sdai.set_public_capability(
        keccak256("mint(uint256)".as_bytes())[0..4].try_into()?,
        true,
    )
    .send()
    .await?;
    lido.set_public_capability(
        keccak256("mint(uint256)".as_bytes())[0..4].try_into()?,
        true,
    )
    .send()
    .await?;

    // Deployer the ERC20 forwarder factory.
    let erc20_forwarder_factory = ERC20ForwarderFactory::deploy(client.clone(), ())?
        .send()
        .await?;

    // Deploy the Hyperdrive factory.
    let factory = {
        HyperdriveFactory::deploy(
            client.clone(),
            ((
                governance_address,        // governance
                governance_address,        // hyperdrive governance
                Vec::<Address>::new(),     // default pausers
                governance_address,        // fee collector
                governance_address,        // sweep collector
                U256::from(60 * 60 * 8),   // checkpoint duration resolution
                U256::from(60 * 60 * 24),  // min checkpoint duration
                U256::from(60 * 60 * 24),  // max checkpoint duration
                U256::from(60 * 60 * 7),   // min position duration
                U256::from(60 * 60 * 365), // max position duration
                uint256!(0.01e18),         // min fixed apr
                uint256!(0.2e18),          // max fixed apr
                uint256!(0.01e18),         // min timestretch apr
                uint256!(0.1e18),          // max timestretch apr
                (
                    uint256!(0.001e18),  // min curve fee
                    uint256!(0.0001e18), // min flat fee
                    uint256!(0.15e18),   // min governance lp fee
                    uint256!(0.03e18),   // min governance zombie fee
                ),
                (
                    uint256!(0.01e18),  // max curve fee
                    uint256!(0.001e18), // max flat fee
                    uint256!(0.15e18),  // max governance lp fee
                    uint256!(0.03e18),  // max governance zombie fee
                ),
                erc20_forwarder_factory.address(),
                erc20_forwarder_factory.erc20link_hash().await?,
            ),),
        )?
        .send()
        .await?
    };

    // Deploy the ERC4626 deployer coordinator.
    let core_deployer = ERC4626HyperdriveCoreDeployer::deploy(client.clone(), ())?
        .send()
        .await?;
    let target0 = ERC4626Target0Deployer::deploy(client.clone(), ())?
        .send()
        .await?;
    let target1 = ERC4626Target1Deployer::deploy(client.clone(), ())?
        .send()
        .await?;
    let target2 = ERC4626Target2Deployer::deploy(client.clone(), ())?
        .send()
        .await?;
    let target3 = ERC4626Target3Deployer::deploy(client.clone(), ())?
        .send()
        .await?;
    let target4 = ERC4626Target4Deployer::deploy(client.clone(), ())?
        .send()
        .await?;
    ERC4626HyperdriveDeployerCoordinator::deploy(
        client.clone(),
        (
            factory.address(),
            core_deployer.address(),
            target0.address(),
            target1.address(),
            target2.address(),
            target3.address(),
            target4.address(),
        ),
    )?
    .send()
    .await?;

    // Deploy the stETH deployer coordinator.
    let steth_deployer_coordinator = {
        let core_deployer = StETHHyperdriveCoreDeployer::deploy(client.clone(), ())?
            .send()
            .await?;
        let target0 = StETHTarget0Deployer::deploy(client.clone(), ())?
            .send()
            .await?;
        let target1 = StETHTarget1Deployer::deploy(client.clone(), ())?
            .send()
            .await?;
        let target2 = StETHTarget2Deployer::deploy(client.clone(), ())?
            .send()
            .await?;
        let target3 = StETHTarget3Deployer::deploy(client.clone(), ())?
            .send()
            .await?;
        let target4 = StETHTarget4Deployer::deploy(client.clone(), ())?
            .send()
            .await?;
        StETHHyperdriveDeployerCoordinator::deploy(
            client.clone(),
            (
                factory.address(),
                core_deployer.address(),
                target0.address(),
                target1.address(),
                target2.address(),
                target3.address(),
                target4.address(),
                lido.address(),
            ),
        )?
        .send()
        .await?
    };

    // Deploy the HyperdriveRegistry contract to track familiar instances.
    let hyperdrive_registry = HyperdriveRegistry::deploy(client.clone(), ())?
        .send()
        .await?;
    hyperdrive_registry
        .update_governance(admin_address)
        .send()
        .await?;

    Ok(())
}
