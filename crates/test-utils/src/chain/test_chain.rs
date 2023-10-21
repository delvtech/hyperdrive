use std::{convert::TryFrom, sync::Arc, time::Duration};

use ethers::{
    core::utils::Anvil,
    middleware::SignerMiddleware,
    providers::{Http, Middleware, Provider},
    signers::{coins_bip39::English, LocalWallet, MnemonicBuilder, Signer},
    types::{Address, Bytes, H256, U256},
    utils::AnvilInstance,
};
use eyre::{eyre, Result};
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, uint256};
use hyperdrive_addresses::Addresses;
use hyperdrive_math::get_time_stretch;
use hyperdrive_wrappers::wrappers::{
    erc20_mintable::ERC20Mintable,
    erc4626_data_provider::ERC4626DataProvider,
    erc4626_hyperdrive::ERC4626Hyperdrive,
    i_hyperdrive::{Fees, PoolConfig},
    ierc4626_hyperdrive::IERC4626Hyperdrive,
    mock_erc4626::MockERC4626,
    mock_fixed_point_math::MockFixedPointMath,
    mock_hyperdrive_math::MockHyperdriveMath,
    mock_yield_space_math::MockYieldSpaceMath,
};

use super::{dev_chain::MNEMONIC, Chain, ChainClient};
use crate::{
    agent::Agent,
    constants::MAYBE_ETHEREUM_URL,
    crash_reports::{ActionType, CrashReport},
};

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
        let addresses = Self::deploy(provider.clone(), accounts[0].clone()).await?;

        Ok(Self {
            addresses,
            accounts,
            provider,
            maybe_crash: None,
            _maybe_anvil,
        })
    }

    // TODO: It would be nice to have a function that reproduces the crash using
    // the trade struct.
    //
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

    /// Attempts to reproduce the crash.
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
        match crash_report.trade.action_type {
            // Long
            ActionType::OpenLong => {
                agent
                    .open_long(
                        crash_report.trade.trade_amount.into(),
                        crash_report.trade.slippage_tolerance.map(|u| u.into()),
                    )
                    .await?
            }
            ActionType::CloseLong => {
                agent
                    .close_long(
                        U256::from(crash_report.trade.maturity_time).into(),
                        crash_report.trade.trade_amount.into(),
                    )
                    .await?
            }
            // Short
            ActionType::OpenShort => {
                agent
                    .open_short(
                        crash_report.trade.trade_amount.into(),
                        crash_report.trade.slippage_tolerance.map(|u| u.into()),
                    )
                    .await?
            }
            ActionType::CloseShort => {
                agent
                    .close_short(
                        U256::from(crash_report.trade.maturity_time).into(),
                        crash_report.trade.trade_amount.into(),
                    )
                    .await?
            }
            // LP
            ActionType::AddLiquidity => {
                agent
                    .add_liquidity(crash_report.trade.trade_amount.into())
                    .await?
            }
            ActionType::RemoveLiquidity => {
                agent
                    .remove_liquidity(crash_report.trade.trade_amount.into())
                    .await?
            }
            ActionType::RedeemWithdrawalShares => {
                agent
                    .redeem_withdrawal_shares(crash_report.trade.trade_amount.into())
                    .await?
            }
            // Failure
            _ => return Err(eyre!("Unsupported reproduction action")),
        }

        Ok(())
    }

    async fn deploy(provider: Provider<Http>, signer: LocalWallet) -> Result<Addresses> {
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
        let pool = MockERC4626::deploy(
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
            initial_share_price: uint256!(1e18),
            minimum_share_reserves: uint256!(10e18),
            minimum_transaction_amount: uint256!(0.001e18),
            position_duration: U256::from(60 * 60 * 24 * 365), // 1 year
            checkpoint_duration: U256::from(60 * 60 * 24),     // 1 day
            time_stretch: get_time_stretch(fixed!(0.05e18)).into(), // time stretch for 5% rate
            governance: client.address(),
            fee_collector: client.address(),
            fees: Fees {
                curve: uint256!(0.05e18),
                flat: uint256!(0.0005e18),
                governance: uint256!(0.15e18),
            },
            oracle_size: uint256!(10),
            update_gap: U256::from(60 * 60), // 1 hour,
        };
        let data_provider = ERC4626DataProvider::deploy(
            client.clone(),
            (
                config.clone(),
                H256::zero(),
                Address::zero(),
                pool.address(),
            ),
        )?
        .send()
        .await?;
        let erc4626_hyperdrive = ERC4626Hyperdrive::deploy(
            client.clone(),
            (
                config,
                data_provider.address(),
                H256::zero(),
                Address::zero(),
                pool.address(),
                Vec::<U256>::new(),
            ),
        )?
        .send()
        .await?;

        Ok(Addresses {
            base: base.address(),
            hyperdrive: erc4626_hyperdrive.address(),
        })
    }

    // TODO: Put the TODOs into an issue for the v0.0.17 release.
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
        let hyperdrive = IERC4626Hyperdrive::new(addresses.hyperdrive, client.clone());

        // Get the contract addresses of the vault and the data provider.
        //
        // HACK(jalextowle): This getter is new, so we hardcode the address
        // to the competition's data provider until the v0.0.17 release.
        // let data_provider_address = hyperdrive.data_provider().call().await?;
        let data_provider_address =
            "0x9bd03768a7DCc129555dE410FF8E85528A4F88b5".parse::<Address>()?;
        let vault_address = hyperdrive.pool().call().await?;

        // Deploy templates for each of the contracts that should be etched and
        // get a list of targets and templates. In order for the contracts to
        // have the same behavior after etching, the storage layout needs to be
        // identical, and we must faithfully copy over the immutables from the
        // original contracts to the templates.
        let etch_pairs = {
            let mut pairs = Vec::new();

            // TODO: We should set `isCompetitionMode` to the real value.
            //
            // Deploy the base token template.
            let base = ERC20Mintable::new(addresses.base, client.clone());
            let name = base.name().call().await?;
            let symbol = base.symbol().call().await?;
            let decimals = base.decimals().call().await?;
            let base_template = ERC20Mintable::deploy(
                client.clone(),
                (name, symbol, decimals, Address::zero(), false),
            )?
            .send()
            .await?;
            pairs.push((addresses.base, base_template.address()));

            // TODO: We should set `isCompetitionMode` to the real value.
            //
            // Deploy the vault template.
            let vault = MockERC4626::new(vault_address, client.clone());
            let asset = vault.asset().call().await?;
            let name = vault.name().call().await?;
            let symbol = vault.symbol().call().await?;
            let vault_template = MockERC4626::deploy(
                client.clone(),
                (asset, name, symbol, uint256!(0), Address::zero(), false),
            )?
            .send()
            .await?;
            pairs.push((vault_address, vault_template.address()));

            // Deploy the data provider template.
            let config = hyperdrive.get_pool_config().call().await?;
            let linker_code_hash = hyperdrive.linker_code_hash().call().await?;
            let factory = hyperdrive.factory().call().await?;
            let data_provider_template = ERC4626DataProvider::deploy(
                client.clone(),
                (config.clone(), linker_code_hash, factory, vault_address),
            )?
            .send()
            .await?;
            pairs.push((data_provider_address, data_provider_template.address()));

            // Deploy the hyperdrive template.
            let hyperdrive_template = ERC4626Hyperdrive::deploy(
                client.clone(),
                (
                    config,
                    data_provider_address,
                    linker_code_hash,
                    factory,
                    vault_address,
                    Vec::<Address>::new(),
                ),
            )?
            .send()
            .await?;
            pairs.push((addresses.hyperdrive, hyperdrive_template.address()));

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
                .arg("--code-size-limit")
                .arg("120000")
                .arg("--disable-block-gas-limit")
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
        let mock_yield_space_math = MockYieldSpaceMath::deploy(client.clone(), ())?
            .send()
            .await?;

        Ok(Self {
            chain,
            mock_fixed_point_math,
            mock_hyperdrive_math,
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

    pub fn mock_yield_space_math(&self) -> MockYieldSpaceMath<ChainClient> {
        self.mock_yield_space_math.clone()
    }
}

#[cfg(test)]
mod tests {
    use fixed_point_macros::uint256;
    use hyperdrive_wrappers::wrappers::{
        erc20_mintable::ERC20Mintable,
        i_hyperdrive::{IHyperdrive, Options},
    };

    use super::*;

    #[tokio::test]
    async fn test_deploy() -> Result<()> {
        let chain = TestChain::new(1).await?;
        let client = chain.client(chain.accounts()[0].clone()).await?;
        let base = ERC20Mintable::new(chain.addresses.base, client.clone());
        let hyperdrive = IHyperdrive::new(chain.addresses.hyperdrive, client.clone());

        // Verify that the addresses are non-zero.
        assert_ne!(chain.addresses, Addresses::default());

        // Verify that the pool config is correct.
        let config = hyperdrive.get_pool_config().call().await?;
        assert_eq!(config.base_token, chain.addresses.base);
        assert_eq!(config.initial_share_price, uint256!(1e18));
        assert_eq!(config.minimum_share_reserves, uint256!(10e18));
        assert_eq!(config.position_duration, U256::from(60 * 60 * 24 * 365));
        assert_eq!(config.checkpoint_duration, U256::from(60 * 60 * 24));
        assert_eq!(
            config.time_stretch,
            get_time_stretch(fixed!(0.05e18)).into()
        );
        assert_eq!(config.governance, client.address());
        assert_eq!(config.fee_collector, client.address());
        assert_eq!(
            config.fees,
            Fees {
                curve: uint256!(0.05e18),
                flat: uint256!(0.0005e18),
                governance: uint256!(0.15e18),
            }
        );
        assert_eq!(config.oracle_size, uint256!(10));
        assert_eq!(config.update_gap, U256::from(60 * 60));

        // Initialize the pool.
        let contribution = uint256!(100e18);
        base.mint(contribution).send().await?;
        base.approve(hyperdrive.address(), contribution)
            .send()
            .await?;
        hyperdrive
            .initialize(
                contribution,
                uint256!(0.05e18),
                Options {
                    destination: client.address(),
                    as_base: true,
                    extra_data: [].into(),
                },
            )
            .send()
            .await?;

        Ok(())
    }
}
