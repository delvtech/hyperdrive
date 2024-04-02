use std::{sync::Arc, time::Duration};

use ethers::{
    core::utils::{keccak256, Anvil},
    middleware::SignerMiddleware,
    prelude::EthLogDecode,
    providers::{Http, Middleware, Provider},
    signers::{coins_bip39::English, LocalWallet, MnemonicBuilder, Signer},
    types::{Address, Bytes, U256},
    utils::AnvilInstance,
};
use eyre::{eyre, Result};
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, uint256};
use hyperdrive_addresses::Addresses;
use hyperdrive_math::calculate_time_stretch;
use hyperdrive_wrappers::wrappers::{
    erc20_forwarder_factory::ERC20ForwarderFactory,
    erc20_mintable::ERC20Mintable,
    erc4626_hyperdrive::ERC4626Hyperdrive,
    erc4626_hyperdrive_core_deployer::ERC4626HyperdriveCoreDeployer,
    erc4626_hyperdrive_deployer_coordinator::ERC4626HyperdriveDeployerCoordinator,
    erc4626_target0::ERC4626Target0,
    erc4626_target0_deployer::ERC4626Target0Deployer,
    erc4626_target1::ERC4626Target1,
    erc4626_target1_deployer::ERC4626Target1Deployer,
    erc4626_target2::ERC4626Target2,
    erc4626_target2_deployer::ERC4626Target2Deployer,
    erc4626_target3::ERC4626Target3,
    erc4626_target3_deployer::ERC4626Target3Deployer,
    erc4626_target4::ERC4626Target4,
    erc4626_target4_deployer::ERC4626Target4Deployer,
    etching_vault::EtchingVault,
    hyperdrive_factory::{
        Fees as FactoryFees, HyperdriveFactory, HyperdriveFactoryEvents, Options, PoolDeployConfig,
    },
    ihyperdrive::{Fees, IHyperdrive, PoolConfig},
    mock_erc4626::MockERC4626,
    mock_fixed_point_math::MockFixedPointMath,
    mock_hyperdrive_math::MockHyperdriveMath,
    mock_lido::MockLido,
    mock_lp_math::MockLPMath,
    mock_yield_space_math::MockYieldSpaceMath,
    steth_hyperdrive_core_deployer::StETHHyperdriveCoreDeployer,
    steth_hyperdrive_deployer_coordinator::StETHHyperdriveDeployerCoordinator,
    steth_target0_deployer::StETHTarget0Deployer,
    steth_target1_deployer::StETHTarget1Deployer,
    steth_target2_deployer::StETHTarget2Deployer,
    steth_target3_deployer::StETHTarget3Deployer,
    steth_target4_deployer::StETHTarget4Deployer,
};
use serde::{Deserialize, Deserializer, Serialize};

use super::{dev_chain::MNEMONIC, Chain, ChainClient};
use crate::{
    agent::{Agent, TxOptions},
    constants::MAYBE_ETHEREUM_URL,
    crash_reports::{ActionType, CrashReport},
};

fn deserialize_u256<'de, D>(deserializer: D) -> Result<U256, D::Error>
where
    D: Deserializer<'de>,
{
    let dec_string: String = Deserialize::deserialize(deserializer)?;
    let u256 = U256::from_dec_str(&dec_string).map_err(serde::de::Error::custom)?;
    Ok(u256)
}

/// A configuration for a test chain that specifies the factory parameters,
/// the base token parameters, the lido parameters, and the parameters for an
/// ERC4626 and a stETH hyperdrive pool.
#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(default)]
pub struct TestChainConfig {
    // admin configuration
    admin: Address,
    is_competition_mode: bool,
    // base token configuration
    base_token_name: String,
    base_token_symbol: String,
    base_token_decimals: u8,
    // vault configuration
    vault_name: String,
    vault_symbol: String,
    #[serde(deserialize_with = "deserialize_u256")]
    vault_starting_rate: U256,
    // lido configuration
    #[serde(deserialize_with = "deserialize_u256")]
    lido_starting_rate: U256,
    // factory configuration
    #[serde(deserialize_with = "deserialize_u256")]
    factory_checkpoint_duration_resolution: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    factory_min_checkpoint_duration: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    factory_max_checkpoint_duration: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    factory_min_position_duration: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    factory_max_position_duration: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    factory_min_fixed_apr: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    factory_max_fixed_apr: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    factory_min_time_stretch_apr: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    factory_max_time_stretch_apr: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    factory_min_curve_fee: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    factory_min_flat_fee: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    factory_min_governance_lp_fee: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    factory_min_governance_zombie_fee: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    factory_max_curve_fee: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    factory_max_flat_fee: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    factory_max_governance_lp_fee: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    factory_max_governance_zombie_fee: U256,
    // erc4626 hyperdrive configuration
    #[serde(deserialize_with = "deserialize_u256")]
    erc4626_hyperdrive_contribution: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    erc4626_hyperdrive_fixed_apr: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    erc4626_hyperdrive_time_stretch_apr: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    erc4626_hyperdrive_minimum_share_reserves: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    erc4626_hyperdrive_minimum_transaction_amount: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    erc4626_hyperdrive_position_duration: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    erc4626_hyperdrive_checkpoint_duration: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    erc4626_hyperdrive_curve_fee: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    erc4626_hyperdrive_flat_fee: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    erc4626_hyperdrive_governance_lp_fee: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    erc4626_hyperdrive_governance_zombie_fee: U256,
    // steth hyperdrive configuration
    #[serde(deserialize_with = "deserialize_u256")]
    steth_hyperdrive_contribution: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    steth_hyperdrive_fixed_apr: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    steth_hyperdrive_time_stretch_apr: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    steth_hyperdrive_minimum_share_reserves: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    steth_hyperdrive_minimum_transaction_amount: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    steth_hyperdrive_position_duration: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    steth_hyperdrive_checkpoint_duration: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    steth_hyperdrive_curve_fee: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    steth_hyperdrive_flat_fee: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    steth_hyperdrive_governance_lp_fee: U256,
    #[serde(deserialize_with = "deserialize_u256")]
    steth_hyperdrive_governance_zombie_fee: U256,
}

impl Default for TestChainConfig {
    fn default() -> Self {
        Self {
            // admin configuration
            admin: Address::zero(),
            is_competition_mode: false,
            // base token configuration
            base_token_name: "Base".to_string(),
            base_token_symbol: "BASE".to_string(),
            base_token_decimals: 18,
            // vault configuration
            vault_name: "Delvnet Yield Source".to_string(),
            vault_symbol: "DELV".to_string(),
            vault_starting_rate: uint256!(0.05e18),
            // lido configuration
            lido_starting_rate: uint256!(0.035e18),
            // factory configuration
            factory_checkpoint_duration_resolution: U256::from(60 * 60), // 1 hour
            factory_min_checkpoint_duration: U256::from(60 * 60),        // 1 hour
            factory_max_checkpoint_duration: U256::from(60 * 60 * 24),   // 1 day
            factory_min_position_duration: U256::from(60 * 60 * 24 * 7), // 7 days
            factory_max_position_duration: U256::from(60 * 60 * 24 * 365 * 10), // 10 years
            factory_min_fixed_apr: uint256!(0.01e18),
            factory_max_fixed_apr: uint256!(0.5e18),
            factory_min_time_stretch_apr: uint256!(0.01e18),
            factory_max_time_stretch_apr: uint256!(0.5e18),
            factory_min_curve_fee: uint256!(0.0001e18),
            factory_min_flat_fee: uint256!(0.0001e18),
            factory_min_governance_lp_fee: uint256!(0.15e18),
            factory_min_governance_zombie_fee: uint256!(0.03e18),
            factory_max_curve_fee: uint256!(0.1e18),
            factory_max_flat_fee: uint256!(0.001e18),
            factory_max_governance_lp_fee: uint256!(0.15e18),
            factory_max_governance_zombie_fee: uint256!(0.03e18),
            // erc4626 hyperdrive configuration
            erc4626_hyperdrive_contribution: uint256!(100_000_000e18),
            erc4626_hyperdrive_fixed_apr: uint256!(0.05e18),
            erc4626_hyperdrive_time_stretch_apr: uint256!(0.05e18),
            erc4626_hyperdrive_minimum_share_reserves: uint256!(10e18),
            erc4626_hyperdrive_minimum_transaction_amount: uint256!(0.001e18),
            erc4626_hyperdrive_position_duration: U256::from(60 * 60 * 24 * 7), // 7 days
            erc4626_hyperdrive_checkpoint_duration: U256::from(60 * 60),        // 1 hour
            erc4626_hyperdrive_curve_fee: uint256!(0.01e18),
            erc4626_hyperdrive_flat_fee: uint256!(0.0005e18) / uint256!(52), // 0.05% APR
            erc4626_hyperdrive_governance_lp_fee: uint256!(0.15e18),
            erc4626_hyperdrive_governance_zombie_fee: uint256!(0.03e18),
            // steth hyperdrive configuration
            steth_hyperdrive_contribution: uint256!(50_000e18),
            steth_hyperdrive_fixed_apr: uint256!(0.035e18),
            steth_hyperdrive_time_stretch_apr: uint256!(0.035e18),
            steth_hyperdrive_minimum_share_reserves: uint256!(1e15),
            steth_hyperdrive_minimum_transaction_amount: uint256!(1e15),
            steth_hyperdrive_position_duration: U256::from(60 * 60 * 24 * 7), // 7 days
            steth_hyperdrive_checkpoint_duration: U256::from(60 * 60),        // 1 hour
            steth_hyperdrive_curve_fee: uint256!(0.01e18),
            steth_hyperdrive_flat_fee: uint256!(0.0005e18) / uint256!(52), // 0.05% APR
            steth_hyperdrive_governance_lp_fee: uint256!(0.15e18),
            steth_hyperdrive_governance_zombie_fee: uint256!(0.03e18),
        }
    }
}

/// A local anvil instance with the Hyperdrive contracts deployed.
#[derive(Clone)]
pub struct TestChain {
    provider: Provider<Http>,
    addresses: Addresses,
    accounts: Vec<LocalWallet>,
    maybe_crash: Option<CrashReport>,
    _maybe_anvil: Option<Arc<AnvilInstance>>,
}

#[async_trait::async_trait]
impl Chain for TestChain {
    fn provider(&self) -> Provider<Http> {
        self.provider.clone()
    }

    fn accounts(&self) -> Vec<LocalWallet> {
        self.accounts.clone()
    }

    fn addresses(&self) -> Addresses {
        self.addresses.clone()
    }
}

impl TestChain {
    /// Instantiates a test chain with a fresh Hyperdrive deployment.
    pub async fn new(num_accounts: usize) -> Result<Self> {
        if num_accounts == 0 {
            panic!("cannot create a test chain with zero accounts");
        }

        // Connect to the anvil node.
        let (provider, _maybe_anvil) = Self::connect().await?;

        // Generate a set of accounts from the default mnemonic and fund them.
        let accounts = Self::fund_accounts(&provider, num_accounts).await?;

        // Deploy the Hyperdrive contracts.
        let addresses = Self::test_deploy(provider.clone(), accounts[0].clone()).await?;

        Ok(Self {
            addresses,
            accounts,
            provider,
            maybe_crash: None,
            _maybe_anvil,
        })
    }

    pub async fn new_with_factory(num_accounts: usize, config: TestChainConfig) -> Result<Self> {
        if num_accounts == 0 {
            panic!("cannot create a test chain with zero accounts");
        }

        // Connect to the anvil node.
        let (provider, _maybe_anvil) = Self::connect().await?;

        // Generate a set of accounts from the default mnemonic and fund them.
        let accounts = Self::fund_accounts(&provider, num_accounts).await?;

        // Deploy the Hyperdrive contracts.
        let addresses = Self::full_deploy(provider.clone(), accounts[0].clone(), config).await?;

        Ok(Self {
            addresses,
            accounts,
            provider,
            maybe_crash: None,
            _maybe_anvil,
        })
    }

    /// Attempts to reproduce a crash from a crash report.
    ///
    /// This function sets up a reproduction environment using the information
    /// provided in the crash report. In particular, it has the following
    /// features:
    ///  - Connects to the anvil node specified by `HYPERDRIVE_ETHEREUM_URL`
    ///    (or spawns a new one if no url is provided).
    ///  - Loads the chain state from the dump file specified in the crash
    ///    report.
    ///  - Etches the latest compiled versions of the smart contracts onto the
    ///    Hyperdrive instance and dependency contracts so that the contracts
    ///    can easily be debugged in the reproduction environment.
    /// -  Creates a set of accounts using the default mnemonic and funds them
    ///    with ether.
    pub async fn load_crash(crash_report_path: &str) -> Result<Self> {
        // Connect to the anvil node.
        let (provider, _maybe_anvil) = Self::connect().await?;

        // Attempt to load the crash report from the provided path.
        let crash_report = {
            let file = std::fs::File::open(crash_report_path)?;
            serde_json::from_reader::<_, CrashReport>(file)?
        };

        // Load the chain state from the dump.
        provider
            .request::<[Bytes; 1], bool>("anvil_loadState", [crash_report.state_dump.clone()])
            .await?;

        // Etch the latest contract bytecode onto the contract addresses.
        let accounts = Self::fund_accounts(&provider, 1).await?;
        Self::etch(&provider, accounts[0].clone(), &crash_report.addresses).await?;

        // Advance the chain to the timestamp of the crash.
        provider
            .request::<[U256; 1], _>(
                "anvil_setNextBlockTimestamp",
                [crash_report.block_timestamp.into()],
            )
            .await?;
        provider
            .request::<[U256; 1], _>("anvil_mine", [1.into()])
            .await?;

        Ok(Self {
            addresses: crash_report.addresses.clone(),
            accounts,
            provider,
            maybe_crash: Some(crash_report),
            _maybe_anvil,
        })
    }

    /// Attempts to reproduce the crash that the TestChain was loaded with.
    pub async fn reproduce_crash(&self) -> Result<()> {
        let crash_report = if let Some(crash_report) = &self.maybe_crash {
            crash_report
        } else {
            return Err(eyre!("cannot reproduce crash without a crash report"));
        };

        // Impersonate the agent that experienced the crash.
        self.provider
            .request::<[Address; 1], _>(
                "anvil_impersonateAccount",
                [crash_report.agent_info.address],
            )
            .await?;
        let mut agent = Agent::new(
            self.client(self.accounts()[0].clone()).await?,
            crash_report.addresses.clone(),
            None,
        )
        .await?;

        // Attempt to reproduce the crash by running the trade that failed.
        let tx_options = Some(TxOptions::new().from(crash_report.agent_info.address));
        match crash_report.trade.action_type {
            // Long
            ActionType::OpenLong => {
                agent
                    .open_long(
                        crash_report.trade.trade_amount.into(),
                        crash_report.trade.slippage_tolerance.map(|u| u.into()),
                        tx_options,
                    )
                    .await?
            }
            ActionType::CloseLong => {
                agent
                    .close_long(
                        U256::from(crash_report.trade.maturity_time).into(),
                        crash_report.trade.trade_amount.into(),
                        tx_options,
                    )
                    .await?
            }
            // Short
            ActionType::OpenShort => {
                agent
                    .open_short(
                        crash_report.trade.trade_amount.into(),
                        crash_report.trade.slippage_tolerance.map(|u| u.into()),
                        tx_options,
                    )
                    .await?
            }
            ActionType::CloseShort => {
                agent
                    .close_short(
                        U256::from(crash_report.trade.maturity_time).into(),
                        crash_report.trade.trade_amount.into(),
                        tx_options,
                    )
                    .await?
            }
            // LP
            ActionType::AddLiquidity => {
                agent
                    .add_liquidity(crash_report.trade.trade_amount.into(), tx_options)
                    .await?
            }
            ActionType::RemoveLiquidity => {
                agent
                    .remove_liquidity(crash_report.trade.trade_amount.into(), tx_options)
                    .await?
            }
            ActionType::RedeemWithdrawalShares => {
                agent
                    .redeem_withdrawal_shares(crash_report.trade.trade_amount.into(), tx_options)
                    .await?
            }
            // Failure
            _ => return Err(eyre!("Unsupported reproduction action")),
        }

        Ok(())
    }

    /// Deploys a fresh instance of Hyperdrive.
    async fn test_deploy(provider: Provider<Http>, signer: LocalWallet) -> Result<Addresses> {
        // Deploy the base token and vault.
        let client = Arc::new(SignerMiddleware::new(
            provider.clone(),
            signer.with_chain_id(provider.get_chainid().await?.low_u64()),
        ));
        let base = ERC20Mintable::deploy(
            client.clone(),
            (
                "Base".to_string(),
                "BASE".to_string(),
                18_u8,
                Address::zero(),
                false,
            ),
        )?
        .send()
        .await?;
        let vault = MockERC4626::deploy(
            client.clone(),
            (
                base.address(),
                "Mock ERC4626 Vault".to_string(),
                "MOCK".to_string(),
                uint256!(0.05e18),
                Address::zero(),
                false,
            ),
        )?
        .send()
        .await?;

        // Deploy the Hyperdrive instance.
        let config = PoolConfig {
            base_token: base.address(),
            vault_shares_token: vault.address(),
            linker_factory: Address::from_low_u64_be(1),
            linker_code_hash: [1; 32],
            initial_vault_share_price: uint256!(1e18),
            minimum_share_reserves: uint256!(10e18),
            minimum_transaction_amount: uint256!(0.001e18),
            position_duration: U256::from(60 * 60 * 24 * 365), // 1 year
            checkpoint_duration: U256::from(60 * 60 * 24),     // 1 day
            time_stretch: calculate_time_stretch(
                fixed!(0.05e18),
                U256::from(60 * 60 * 24 * 365).into(),
            )
            .into(), // time stretch for 5% rate
            fee_collector: client.address(),
            sweep_collector: client.address(),
            governance: client.address(),
            fees: Fees {
                curve: uint256!(0.05e18),
                flat: uint256!(0.0005e18),
                governance_lp: uint256!(0.15e18),
                governance_zombie: uint256!(0.15e18),
            },
        };
        let target0 = ERC4626Target0::deploy(client.clone(), (config.clone(),))?
            .send()
            .await?;
        let target1 = ERC4626Target1::deploy(client.clone(), (config.clone(),))?
            .send()
            .await?;
        let target2 = ERC4626Target2::deploy(client.clone(), (config.clone(),))?
            .send()
            .await?;
        let target3 = ERC4626Target3::deploy(client.clone(), (config.clone(),))?
            .send()
            .await?;
        let target4 = ERC4626Target4::deploy(client.clone(), (config.clone(),))?
            .send()
            .await?;
        let erc4626_hyperdrive = ERC4626Hyperdrive::deploy(
            client.clone(),
            (
                config,
                target0.address(),
                target1.address(),
                target2.address(),
                target3.address(),
                target4.address(),
            ),
        )?
        .send()
        .await?;

        Ok(Addresses {
            base_token: base.address(),
            erc4626_hyperdrive: erc4626_hyperdrive.address(),
            steth_hyperdrive: Address::zero(),
            factory: Address::zero(),
        })
    }

    /// Deploys the full Hyperdrive system equipped with a Hyperdrive Factory,
    /// an ERC4626Hyperdrive instance, and a StETHHyperdrive instance.
    async fn full_deploy(
        provider: Provider<Http>,
        signer: LocalWallet,
        config: TestChainConfig,
    ) -> Result<Addresses> {
        // Set up an ethers client with the provider and signer.
        let client = Arc::new(SignerMiddleware::new(
            provider.clone(),
            signer.with_chain_id(provider.get_chainid().await?.low_u64()),
        ));

        // Deploy the base token and vault.
        let base = ERC20Mintable::deploy(
            client.clone(),
            (
                config.base_token_name,
                config.base_token_symbol,
                config.base_token_decimals,
                client.address(),
                config.is_competition_mode,
            ),
        )?
        .send()
        .await?;
        let vault = MockERC4626::deploy(
            client.clone(),
            (
                base.address(),
                config.vault_name,
                config.vault_symbol,
                config.vault_starting_rate,
                client.address(),
                config.is_competition_mode,
            ),
        )?
        .send()
        .await?;
        if config.is_competition_mode {
            base.set_user_role(vault.address(), 1, true).send().await?;
            base.set_role_capability(
                1,
                keccak256("mint(uint256)".as_bytes())[0..4].try_into()?,
                true,
            )
            .send()
            .await?;
            base.set_role_capability(
                1,
                keccak256("burn(uint256)".as_bytes())[0..4].try_into()?,
                true,
            )
            .send()
            .await?;
        }

        // Deploy the mock Lido system. We fund Lido with 1 eth to start to
        // avoid reverts when we initialize the pool.
        let lido = {
            let lido = MockLido::deploy(
                client.clone(),
                (
                    config.lido_starting_rate,
                    client.address(),
                    config.is_competition_mode,
                ),
            )?
            .send()
            .await?;
            provider
                .request(
                    "anvil_setBalance",
                    (
                        client.address(),
                        client.get_balance(client.address(), None).await? + U256::one(),
                    ),
                )
                .await?;
            lido.submit(Address::zero())
                .value(uint256!(1e18))
                .send()
                .await?;
            lido
        };

        // Deployer the ERC20 forwarder factory.
        let erc20_forwarder_factory = ERC20ForwarderFactory::deploy(client.clone(), ())?
            .send()
            .await?;

        // Deploy the Hyperdrive factory.
        let factory = {
            HyperdriveFactory::deploy(
                client.clone(),
                ((
                    client.address(),   // governance
                    config.admin,       // hyperdrive governance
                    vec![config.admin], // default pausers
                    config.admin,       // fee collector
                    config.admin,       // sweep collector
                    config.factory_checkpoint_duration_resolution,
                    config.factory_min_checkpoint_duration,
                    config.factory_max_checkpoint_duration,
                    config.factory_min_position_duration,
                    config.factory_max_position_duration,
                    config.factory_min_fixed_apr,
                    config.factory_max_fixed_apr,
                    config.factory_min_time_stretch_apr,
                    config.factory_max_time_stretch_apr,
                    (
                        config.factory_min_curve_fee,
                        config.factory_min_flat_fee,
                        config.factory_min_governance_lp_fee,
                        config.factory_min_governance_zombie_fee,
                    ),
                    (
                        config.factory_max_curve_fee,
                        config.factory_max_flat_fee,
                        config.factory_max_governance_lp_fee,
                        config.factory_max_governance_zombie_fee,
                    ),
                    erc20_forwarder_factory.address(),
                    erc20_forwarder_factory.erc20link_hash().await?,
                ),),
            )?
            .send()
            .await?
        };

        // Deploy the ERC4626Hyperdrive deployers and add them to the factory.
        let erc4626_deployer_coordinator = {
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
                    core_deployer.address(),
                    target0.address(),
                    target1.address(),
                    target2.address(),
                    target3.address(),
                    target4.address(),
                ),
            )?
            .send()
            .await?
        };
        factory
            .add_deployer_coordinator(erc4626_deployer_coordinator.address())
            .send()
            .await?;

        // Deploy and initialize an initial ERC4626Hyperdrive instance.
        let erc4626_hyperdrive = {
            base.mint_with_destination(client.address(), config.erc4626_hyperdrive_contribution)
                .send()
                .await?;
            base.approve(
                erc4626_deployer_coordinator.address(),
                config.erc4626_hyperdrive_contribution,
            )
            .send()
            .await?;
            let pool_config = PoolDeployConfig {
                fee_collector: factory.fee_collector().call().await?,
                sweep_collector: factory.sweep_collector().call().await?,
                governance: factory.hyperdrive_governance().call().await?,
                linker_factory: factory.linker_factory().call().await?,
                linker_code_hash: factory.linker_code_hash().call().await?,
                time_stretch: uint256!(0),
                base_token: base.address(),
                vault_shares_token: vault.address(),
                minimum_share_reserves: config.erc4626_hyperdrive_minimum_share_reserves,
                minimum_transaction_amount: config.erc4626_hyperdrive_minimum_transaction_amount,
                position_duration: config.erc4626_hyperdrive_position_duration,
                checkpoint_duration: config.erc4626_hyperdrive_checkpoint_duration,
                fees: FactoryFees {
                    curve: config.erc4626_hyperdrive_curve_fee,
                    flat: config.erc4626_hyperdrive_flat_fee,
                    governance_lp: config.erc4626_hyperdrive_governance_lp_fee,
                    governance_zombie: config.erc4626_hyperdrive_governance_zombie_fee,
                },
            };
            factory
                .deploy_target(
                    [0x01; 32],
                    erc4626_deployer_coordinator.address(),
                    pool_config.clone(),
                    Vec::new().into(),
                    config.erc4626_hyperdrive_fixed_apr,
                    config.erc4626_hyperdrive_time_stretch_apr,
                    U256::from(0),
                    [0x01; 32],
                )
                .send()
                .await?;
            factory
                .deploy_target(
                    [0x01; 32],
                    erc4626_deployer_coordinator.address(),
                    pool_config.clone(),
                    Vec::new().into(),
                    config.erc4626_hyperdrive_fixed_apr,
                    config.erc4626_hyperdrive_time_stretch_apr,
                    U256::from(1),
                    [0x01; 32],
                )
                .send()
                .await?;
            factory
                .deploy_target(
                    [0x01; 32],
                    erc4626_deployer_coordinator.address(),
                    pool_config.clone(),
                    Vec::new().into(),
                    config.erc4626_hyperdrive_fixed_apr,
                    config.erc4626_hyperdrive_time_stretch_apr,
                    U256::from(2),
                    [0x01; 32],
                )
                .send()
                .await?;
            factory
                .deploy_target(
                    [0x01; 32],
                    erc4626_deployer_coordinator.address(),
                    pool_config.clone(),
                    Vec::new().into(),
                    config.erc4626_hyperdrive_fixed_apr,
                    config.erc4626_hyperdrive_time_stretch_apr,
                    U256::from(3),
                    [0x01; 32],
                )
                .send()
                .await?;
            factory
                .deploy_target(
                    [0x01; 32],
                    erc4626_deployer_coordinator.address(),
                    pool_config.clone(),
                    Vec::new().into(),
                    config.erc4626_hyperdrive_fixed_apr,
                    config.erc4626_hyperdrive_time_stretch_apr,
                    U256::from(4),
                    [0x01; 32],
                )
                .send()
                .await?;
            let tx = factory
                .deploy_and_initialize(
                    [0x01; 32],
                    erc4626_deployer_coordinator.address(),
                    pool_config,
                    Vec::new().into(),
                    config.erc4626_hyperdrive_contribution,
                    config.erc4626_hyperdrive_fixed_apr,
                    config.erc4626_hyperdrive_time_stretch_apr,
                    Options {
                        as_base: true,
                        destination: client.address(),
                        extra_data: Vec::new().into(),
                    },
                    [0x01; 32],
                )
                .send()
                .await?
                .await?
                .unwrap();
            let logs = tx
                .logs
                .into_iter()
                .filter_map(|log| {
                    if let Ok(HyperdriveFactoryEvents::DeployedFilter(log)) =
                        HyperdriveFactoryEvents::decode_log(&log.into())
                    {
                        Some(log)
                    } else {
                        None
                    }
                })
                .collect::<Vec<_>>();
            logs[0].clone().hyperdrive
        };

        // Deploy the StETHHyperdrive deployers and add them to the factory.
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
        factory
            .add_deployer_coordinator(steth_deployer_coordinator.address())
            .send()
            .await?;

        // Deploy and initialize an initial StETHHyperdrive instance.
        let steth_hyperdrive = {
            provider
                .request(
                    "anvil_setBalance",
                    (
                        client.address(),
                        client.get_balance(client.address(), None).await?
                            + config.steth_hyperdrive_contribution,
                    ),
                )
                .await?;
            let pool_config = PoolDeployConfig {
                fee_collector: factory.fee_collector().call().await?,
                sweep_collector: factory.sweep_collector().call().await?,
                governance: factory.hyperdrive_governance().call().await?,
                linker_factory: factory.linker_factory().call().await?,
                linker_code_hash: factory.linker_code_hash().call().await?,
                time_stretch: uint256!(0),
                base_token: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE".parse()?,
                vault_shares_token: lido.address(),
                minimum_share_reserves: config.steth_hyperdrive_minimum_share_reserves,
                minimum_transaction_amount: config.steth_hyperdrive_minimum_transaction_amount,
                position_duration: config.steth_hyperdrive_position_duration,
                checkpoint_duration: config.steth_hyperdrive_checkpoint_duration,
                fees: FactoryFees {
                    curve: config.steth_hyperdrive_curve_fee,
                    flat: config.steth_hyperdrive_flat_fee,
                    governance_lp: config.steth_hyperdrive_governance_lp_fee,
                    governance_zombie: config.steth_hyperdrive_governance_zombie_fee,
                },
            };
            factory
                .deploy_target(
                    [0x02; 32],
                    steth_deployer_coordinator.address(),
                    pool_config.clone(),
                    Vec::new().into(),
                    config.steth_hyperdrive_fixed_apr,
                    config.steth_hyperdrive_time_stretch_apr,
                    U256::from(0),
                    [0x02; 32],
                )
                .send()
                .await?;
            factory
                .deploy_target(
                    [0x02; 32],
                    steth_deployer_coordinator.address(),
                    pool_config.clone(),
                    Vec::new().into(),
                    config.steth_hyperdrive_fixed_apr,
                    config.steth_hyperdrive_time_stretch_apr,
                    U256::from(1),
                    [0x02; 32],
                )
                .send()
                .await?;
            factory
                .deploy_target(
                    [0x02; 32],
                    steth_deployer_coordinator.address(),
                    pool_config.clone(),
                    Vec::new().into(),
                    config.steth_hyperdrive_fixed_apr,
                    config.steth_hyperdrive_time_stretch_apr,
                    U256::from(2),
                    [0x02; 32],
                )
                .send()
                .await?;
            factory
                .deploy_target(
                    [0x02; 32],
                    steth_deployer_coordinator.address(),
                    pool_config.clone(),
                    Vec::new().into(),
                    config.steth_hyperdrive_fixed_apr,
                    config.steth_hyperdrive_time_stretch_apr,
                    U256::from(3),
                    [0x02; 32],
                )
                .send()
                .await?;
            factory
                .deploy_target(
                    [0x02; 32],
                    steth_deployer_coordinator.address(),
                    pool_config.clone(),
                    Vec::new().into(),
                    config.steth_hyperdrive_fixed_apr,
                    config.steth_hyperdrive_time_stretch_apr,
                    U256::from(4),
                    [0x02; 32],
                )
                .send()
                .await?;
            let tx = factory
                .deploy_and_initialize(
                    [0x02; 32],
                    steth_deployer_coordinator.address(),
                    pool_config,
                    Vec::new().into(),
                    config.steth_hyperdrive_contribution,
                    config.steth_hyperdrive_fixed_apr,
                    config.steth_hyperdrive_time_stretch_apr,
                    Options {
                        as_base: true,
                        destination: client.address(),
                        extra_data: Vec::new().into(),
                    },
                    [0x02; 32],
                )
                .value(config.steth_hyperdrive_contribution)
                .send()
                .await?
                .await?
                .unwrap();
            let logs = tx
                .logs
                .into_iter()
                .filter_map(|log| {
                    if let Ok(HyperdriveFactoryEvents::DeployedFilter(log)) =
                        HyperdriveFactoryEvents::decode_log(&log.into())
                    {
                        Some(log)
                    } else {
                        None
                    }
                })
                .collect::<Vec<_>>();
            logs[0].clone().hyperdrive
        };

        // Transfer ownership of the base token, factory, vault, and lido to the
        // admin address now that we're done minting tokens and updating the
        // configuration.
        base.transfer_ownership(config.admin).send().await?;
        vault.transfer_ownership(config.admin).send().await?;
        lido.transfer_ownership(config.admin).send().await?;
        factory.update_governance(config.admin).send().await?;

        Ok(Addresses {
            base_token: base.address(),
            factory: factory.address(),
            erc4626_hyperdrive,
            steth_hyperdrive,
        })
    }

    /// Etches the latest compiled bytecode onto a target instance of Hyperdrive.
    async fn etch(
        provider: &Provider<Http>,
        signer: LocalWallet,
        addresses: &Addresses,
    ) -> Result<()> {
        // Instantiate a hyperdrive contract wrapper to use during the etching
        // process.
        let client = Arc::new(SignerMiddleware::new(
            provider.clone(),
            signer.with_chain_id(provider.get_chainid().await?.low_u64()),
        ));
        let hyperdrive = IHyperdrive::new(addresses.erc4626_hyperdrive, client.clone());

        // Get the contract addresses of the vault and the targets.
        let target0_address = hyperdrive.target_0().call().await?;
        let target1_address = hyperdrive.target_1().call().await?;
        let target2_address = hyperdrive.target_2().call().await?;
        let target3_address = hyperdrive.target_3().call().await?;
        let target4_address = hyperdrive.target_4().call().await?;
        let vault_address = hyperdrive.vault_shares_token().call().await?;

        // Deploy templates for each of the contracts that should be etched and
        // get a list of targets and templates. In order for the contracts to
        // have the same behavior after etching, the storage layout needs to be
        // identical, and we must faithfully copy over the immutables from the
        // original contracts to the templates.
        let etch_pairs = {
            let mut pairs = Vec::new();

            // Deploy the base token template.
            let base = ERC20Mintable::new(addresses.base_token, client.clone());
            let name = base.name().call().await?;
            let symbol = base.symbol().call().await?;
            let decimals = base.decimals().call().await?;
            let is_competition_mode = base.is_competition_mode().call().await?;
            let base_template = ERC20Mintable::deploy(
                client.clone(),
                (name, symbol, decimals, Address::zero(), is_competition_mode),
            )?
            .send()
            .await?;
            pairs.push((addresses.base_token, base_template.address()));

            // Deploy the vault template.
            let vault = MockERC4626::new(vault_address, client.clone());
            let asset = vault.asset().call().await?;
            let name = vault.name().call().await?;
            let symbol = vault.symbol().call().await?;
            let is_competition_mode = vault.is_competition_mode().call().await?;
            let vault_template = MockERC4626::deploy(
                client.clone(),
                (
                    asset,
                    name,
                    symbol,
                    uint256!(0),
                    Address::zero(),
                    is_competition_mode,
                ),
            )?
            .send()
            .await?;
            pairs.push((vault_address, vault_template.address()));

            // Deploy the target0 template.
            let config = hyperdrive.get_pool_config().call().await?;
            let target0_template =
                ERC4626Target0::deploy(client.clone(), (config.clone(), vault_address))?
                    .send()
                    .await?;
            pairs.push((target0_address, target0_template.address()));

            // Deploy the target1 template.
            let target1_template =
                ERC4626Target1::deploy(client.clone(), (config.clone(), vault_address))?
                    .send()
                    .await?;
            pairs.push((target1_address, target1_template.address()));

            // Deploy the target2 template.
            let target2_template =
                ERC4626Target2::deploy(client.clone(), (config.clone(), vault_address))?
                    .send()
                    .await?;
            pairs.push((target2_address, target2_template.address()));

            // Deploy the target3 template.
            let target3_template =
                ERC4626Target3::deploy(client.clone(), (config.clone(), vault_address))?
                    .send()
                    .await?;
            pairs.push((target3_address, target3_template.address()));

            // Deploy the target4 template.
            let target4_template =
                ERC4626Target4::deploy(client.clone(), (config.clone(), vault_address))?
                    .send()
                    .await?;
            pairs.push((target4_address, target4_template.address()));

            // Etch the "etching vault" onto the current vault contract. The
            // etching vault implements `convertToAssets` to return the immutable
            // that was passed on deployment. This is necessary because the
            // ERC4626Hyperdrive instance verifies that the initial vault share price
            // is equal to the `_pricePerVaultShare`.
            let etching_vault_template = EtchingVault::deploy(
                client.clone(),
                (addresses.base_token, config.initial_vault_share_price),
            )?
            .send()
            .await?;
            let code = provider
                .get_code(etching_vault_template.address(), None)
                .await?;
            provider
                .request::<(Address, Bytes), ()>("anvil_setCode", (vault_address, code))
                .await?;

            // Deploy the hyperdrive template.
            let hyperdrive_template = ERC4626Hyperdrive::deploy(
                client.clone(),
                (
                    config,
                    target0_address,
                    target1_address,
                    target2_address,
                    target3_address,
                    target4_address,
                    vault_address,
                    Vec::<Address>::new(),
                ),
            )?
            .send()
            .await?;
            pairs.push((addresses.erc4626_hyperdrive, hyperdrive_template.address()));

            pairs
        };

        // Etch over the original contracts with the template contracts' code.
        for (target, template) in etch_pairs {
            let code = provider.get_code(template, None).await?;
            provider
                .request::<(Address, Bytes), ()>("anvil_setCode", (target, code))
                .await?;
        }

        Ok(())
    }

    /// Generates and funds a set of random accounts with ether.
    async fn fund_accounts(
        provider: &Provider<Http>,
        num_accounts: usize,
    ) -> Result<Vec<LocalWallet>> {
        // Create a set of accounts using the default mnemonic and fund them
        // with ether.
        let mut accounts = vec![];
        let mut builder = MnemonicBuilder::<English>::default().phrase(MNEMONIC);
        for i in 0..num_accounts {
            // Generate the account at the new index using the mnemonic.
            builder = builder.index(i as u32).unwrap();
            let account = builder.build()?;

            // Fund the account with some ether and add it to the list of accounts..
            provider
                .request(
                    "anvil_setBalance",
                    (account.address(), uint256!(100_000e18)),
                )
                .await?;
            accounts.push(account);
        }

        Ok(accounts)
    }

    /// Connect to the ethereum node specified by the `HYPERDRIVE_ETHEREUM_URL`
    /// environment variable. If no url is provided, spawn an in-process anvil
    /// node.
    async fn connect() -> Result<(Provider<Http>, Option<Arc<AnvilInstance>>)> {
        // If an ethereum url is provided, use it. Otherwise, we spawn an
        // in-process anvil node.
        if let Some(ethereum_url) = &*MAYBE_ETHEREUM_URL {
            Ok((
                Provider::<Http>::try_from(ethereum_url)?.interval(Duration::from_millis(1)),
                None,
            ))
        } else {
            let anvil = Anvil::new()
                .arg("--timestamp")
                // NOTE: Anvil can't increase the time or set the time of the
                // next block to a time in the past, so we set the genesis block
                // to 12 AM UTC, January 1, 2000 to avoid issues when reproducing
                // old crash reports.
                .arg("946684800")
                .spawn();
            Ok((
                Provider::<Http>::try_from(anvil.endpoint())?.interval(Duration::from_millis(1)),
                Some(Arc::new(anvil)),
            ))
        }
    }
}

impl TestChain {
    pub async fn snapshot(&self) -> Result<U256> {
        let id = self.provider.request("evm_snapshot", ()).await?;
        Ok(id)
    }

    pub async fn revert<U: Into<U256>>(&self, id: U) -> Result<()> {
        self.provider
            .request::<[U256; 1], bool>("evm_revert", [id.into()])
            .await?;
        Ok(())
    }

    pub async fn increase_time(&self, duration: u128) -> Result<()> {
        self.provider
            .request::<[u128; 1], i128>("anvil_increaseTime", [duration])
            .await?;
        self.provider
            .request::<[u128; 1], ()>("anvil_mine", [1])
            .await?;
        Ok(())
    }

    pub async fn set_balance<U: Into<U256>>(&self, address: Address, balance: U) -> Result<()> {
        self.provider
            .request::<(Address, U256), bool>("anvil_setBalance", (address, balance.into()))
            .await?;
        Ok(())
    }
}

pub struct TestChainWithMocks {
    chain: TestChain,
    mock_fixed_point_math: MockFixedPointMath<ChainClient>,
    mock_hyperdrive_math: MockHyperdriveMath<ChainClient>,
    mock_lp_math: MockLPMath<ChainClient>,
    mock_yield_space_math: MockYieldSpaceMath<ChainClient>,
}

impl TestChainWithMocks {
    pub async fn new(num_accounts: usize) -> Result<Self> {
        let chain = TestChain::new(num_accounts).await?;
        let client = chain.client(chain.accounts()[0].clone()).await?;

        // Deploy the mock contracts.
        let mock_fixed_point_math = MockFixedPointMath::deploy(client.clone(), ())?
            .send()
            .await?;
        let mock_hyperdrive_math = MockHyperdriveMath::deploy(client.clone(), ())?
            .send()
            .await?;
        let mock_lp_math = MockLPMath::deploy(client.clone(), ())?.send().await?;
        let mock_yield_space_math = MockYieldSpaceMath::deploy(client.clone(), ())?
            .send()
            .await?;

        Ok(Self {
            chain,
            mock_fixed_point_math,
            mock_hyperdrive_math,
            mock_lp_math,
            mock_yield_space_math,
        })
    }

    pub fn chain(&self) -> TestChain {
        self.chain.clone()
    }

    pub fn mock_fixed_point_math(&self) -> MockFixedPointMath<ChainClient> {
        self.mock_fixed_point_math.clone()
    }

    pub fn mock_hyperdrive_math(&self) -> MockHyperdriveMath<ChainClient> {
        self.mock_hyperdrive_math.clone()
    }

    pub fn mock_lp_math(&self) -> MockLPMath<ChainClient> {
        self.mock_lp_math.clone()
    }

    pub fn mock_yield_space_math(&self) -> MockYieldSpaceMath<ChainClient> {
        self.mock_yield_space_math.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_deploy_devnet() -> Result<()> {
        let test_chain_config = TestChainConfig::default();
        let chain = TestChain::new_with_factory(1, test_chain_config.clone()).await?;
        let client = chain.client(chain.accounts()[0].clone()).await?;

        // Verify that the addresses are non-zero.
        assert_ne!(chain.addresses, Addresses::default());

        // Verify that the erc4626 pool config is correct.
        let hyperdrive = IHyperdrive::new(chain.addresses.erc4626_hyperdrive, client.clone());
        let config = hyperdrive.get_pool_config().call().await?;
        assert_eq!(config.base_token, chain.addresses.base_token);
        assert_eq!(
            config.minimum_share_reserves,
            test_chain_config.erc4626_hyperdrive_minimum_share_reserves
        );
        assert_eq!(
            config.position_duration,
            test_chain_config.erc4626_hyperdrive_position_duration
        );
        assert_eq!(
            config.checkpoint_duration,
            test_chain_config.erc4626_hyperdrive_checkpoint_duration
        );
        assert_eq!(
            config.time_stretch,
            calculate_time_stretch(
                test_chain_config.erc4626_hyperdrive_time_stretch_apr.into(),
                test_chain_config
                    .erc4626_hyperdrive_position_duration
                    .into(),
            )
            .into()
        );
        assert_eq!(config.governance, test_chain_config.admin);
        assert_eq!(config.fee_collector, test_chain_config.admin);
        assert_eq!(config.sweep_collector, test_chain_config.admin);
        assert_eq!(
            config.fees,
            Fees {
                curve: test_chain_config.erc4626_hyperdrive_curve_fee,
                flat: test_chain_config.erc4626_hyperdrive_flat_fee,
                governance_lp: test_chain_config.erc4626_hyperdrive_governance_lp_fee,
                governance_zombie: test_chain_config.erc4626_hyperdrive_governance_zombie_fee,
            }
        );

        // Verify that the steth pool config is correct.
        let hyperdrive = IHyperdrive::new(chain.addresses.steth_hyperdrive, client.clone());
        let config = hyperdrive.get_pool_config().call().await?;
        assert_eq!(
            config.base_token,
            "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE".parse::<Address>()?
        );
        assert_eq!(
            config.minimum_share_reserves,
            test_chain_config.steth_hyperdrive_minimum_share_reserves
        );
        assert_eq!(
            config.position_duration,
            test_chain_config.steth_hyperdrive_position_duration
        );
        assert_eq!(
            config.checkpoint_duration,
            test_chain_config.steth_hyperdrive_checkpoint_duration
        );
        assert_eq!(
            config.time_stretch,
            calculate_time_stretch(
                test_chain_config.steth_hyperdrive_time_stretch_apr.into(),
                test_chain_config.steth_hyperdrive_position_duration.into(),
            )
            .into()
        );
        assert_eq!(config.governance, test_chain_config.admin);
        assert_eq!(config.fee_collector, test_chain_config.admin);
        assert_eq!(
            config.fees,
            Fees {
                curve: test_chain_config.steth_hyperdrive_curve_fee,
                flat: test_chain_config.steth_hyperdrive_flat_fee,
                governance_lp: test_chain_config.steth_hyperdrive_governance_lp_fee,
                governance_zombie: test_chain_config.steth_hyperdrive_governance_zombie_fee,
            }
        );

        Ok(())
    }

    #[tokio::test]
    async fn test_deploy_testnet() -> Result<()> {
        let mut test_chain_config = TestChainConfig::default();
        test_chain_config.erc4626_hyperdrive_position_duration = U256::from(60 * 60 * 24 * 365);
        test_chain_config.erc4626_hyperdrive_flat_fee = uint256!(0.0005e18);
        test_chain_config.steth_hyperdrive_position_duration = U256::from(60 * 60 * 24 * 365);
        test_chain_config.steth_hyperdrive_flat_fee = uint256!(0.0005e18);
        let chain = TestChain::new_with_factory(1, test_chain_config.clone()).await?;
        let client = chain.client(chain.accounts()[0].clone()).await?;

        // Verify that the addresses are non-zero.
        assert_ne!(chain.addresses, Addresses::default());

        // Verify that the erc4626 pool config is correct.
        let hyperdrive = IHyperdrive::new(chain.addresses.erc4626_hyperdrive, client.clone());
        let config = hyperdrive.get_pool_config().call().await?;
        assert_eq!(config.base_token, chain.addresses.base_token);
        assert_eq!(
            config.minimum_share_reserves,
            test_chain_config.erc4626_hyperdrive_minimum_share_reserves
        );
        assert_eq!(
            config.position_duration,
            test_chain_config.erc4626_hyperdrive_position_duration
        );
        assert_eq!(
            config.checkpoint_duration,
            test_chain_config.erc4626_hyperdrive_checkpoint_duration
        );
        assert_eq!(
            config.time_stretch,
            calculate_time_stretch(
                test_chain_config.erc4626_hyperdrive_time_stretch_apr.into(),
                test_chain_config
                    .erc4626_hyperdrive_position_duration
                    .into(),
            )
            .into()
        );
        assert_eq!(config.governance, test_chain_config.admin);
        assert_eq!(config.fee_collector, test_chain_config.admin);
        assert_eq!(config.sweep_collector, test_chain_config.admin);
        assert_eq!(
            config.fees,
            Fees {
                curve: test_chain_config.erc4626_hyperdrive_curve_fee,
                flat: test_chain_config.erc4626_hyperdrive_flat_fee,
                governance_lp: test_chain_config.erc4626_hyperdrive_governance_lp_fee,
                governance_zombie: test_chain_config.erc4626_hyperdrive_governance_zombie_fee,
            }
        );

        // Verify that the steth pool config is correct.
        let hyperdrive = IHyperdrive::new(chain.addresses.steth_hyperdrive, client.clone());
        let config = hyperdrive.get_pool_config().call().await?;
        assert_eq!(
            config.base_token,
            "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE".parse::<Address>()?
        );
        assert_eq!(
            config.minimum_share_reserves,
            test_chain_config.steth_hyperdrive_minimum_share_reserves
        );
        assert_eq!(
            config.position_duration,
            test_chain_config.steth_hyperdrive_position_duration
        );
        assert_eq!(
            config.checkpoint_duration,
            test_chain_config.steth_hyperdrive_checkpoint_duration
        );
        assert_eq!(
            config.time_stretch,
            calculate_time_stretch(
                test_chain_config.steth_hyperdrive_time_stretch_apr.into(),
                test_chain_config.steth_hyperdrive_position_duration.into(),
            )
            .into()
        );
        assert_eq!(config.governance, test_chain_config.admin);
        assert_eq!(config.fee_collector, test_chain_config.admin);
        assert_eq!(
            config.fees,
            Fees {
                curve: test_chain_config.steth_hyperdrive_curve_fee,
                flat: test_chain_config.steth_hyperdrive_flat_fee,
                governance_lp: test_chain_config.steth_hyperdrive_governance_lp_fee,
                governance_zombie: test_chain_config.steth_hyperdrive_governance_zombie_fee,
            }
        );

        Ok(())
    }
}
