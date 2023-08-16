use std::{convert::TryFrom, sync::Arc, time::Duration};

use ethers::{
    core::utils::Anvil,
    middleware::SignerMiddleware,
    providers::{Http, Middleware, Provider},
    signers::{coins_bip39::English, LocalWallet, MnemonicBuilder, Signer},
    types::{Address, H256, U256},
    utils::AnvilInstance,
};
use eyre::Result;
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, uint256};
use hyperdrive_addresses::Addresses;
use hyperdrive_math::yield_space::State as YieldSpace;
use hyperdrive_wrappers::wrappers::{
    erc20_mintable::ERC20Mintable,
    erc4626_data_provider::ERC4626DataProvider,
    erc4626_hyperdrive::ERC4626Hyperdrive,
    i_hyperdrive::{Fees, PoolConfig},
    mock4626::Mock4626,
};

use crate::dev_chain::MNEMONIC;

/// A local anvil instance with the Hyperdrive contracts deployed.
pub struct TestChain {
    pub provider: Provider<Http>,
    pub addresses: Addresses,
    pub accounts: Vec<LocalWallet>,
    _maybe_anvil: Option<AnvilInstance>,
}

impl TestChain {
    /// Deploys the Hyperdrive contracts to an anvil nodes and sets up some
    /// funded accounts.
    pub async fn new(maybe_ethereum_url: Option<&str>, num_accounts: usize) -> Result<Self> {
        if num_accounts == 0 {
            panic!("cannot create a test chain with zero accounts");
        }

        // If an ethereum url is provided, use it. Otherwise, we spawn an
        // in-process anvil node.
        let (provider, _maybe_anvil) = if let Some(ethereum_url) = maybe_ethereum_url {
            (Provider::<Http>::try_from(ethereum_url)?, None)
        } else {
            let anvil = Anvil::new().spawn();
            (
                Provider::<Http>::try_from(anvil.endpoint())?
                    .interval(Duration::from_millis(10u64)),
                Some(anvil),
            )
        };

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
                .request("anvil_setBalance", (account.address(), uint256!(1_000e18)))
                .await?;
            accounts.push(account);
        }

        // Deploy the Hyperdrive contracts.
        let addresses = Self::deploy(provider.clone(), accounts[0].clone()).await?;

        Ok(Self {
            addresses,
            accounts,
            provider,
            _maybe_anvil,
        })
    }

    pub async fn chain_id(&self) -> Result<u64> {
        let chain_id = self.provider.get_chainid().await?;
        Ok(chain_id.low_u64())
    }

    async fn deploy(provider: Provider<Http>, signer: LocalWallet) -> Result<Addresses> {
        // Deploy the base token and vault.
        let client = Arc::new(SignerMiddleware::new(
            provider.clone(),
            signer.with_chain_id(provider.get_chainid().await?.low_u64()),
        ));
        let base = ERC20Mintable::deploy(client.clone(), ())?.send().await?;
        let pool = Mock4626::deploy(
            client.clone(),
            (
                base.address(),
                "Mock ERC4626 Vault".to_string(),
                "MOCK".to_string(),
            ),
        )?
        .send()
        .await?;

        // Deploy the Hyperdrive instance.
        let config = PoolConfig {
            base_token: base.address(),
            initial_share_price: uint256!(1e18),
            minimum_share_reserves: uint256!(10e18),
            position_duration: U256::from(60 * 60 * 24 * 365), // 1 year
            checkpoint_duration: U256::from(60 * 60 * 24),     // 1 day
            time_stretch: YieldSpace::get_time_stretch(fixed!(0.05e18)).into(), // time stretch for 5% rate
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
}

#[cfg(test)]
mod tests {
    use ethers::middleware::SignerMiddleware;
    use fixed_point_macros::uint256;
    use hyperdrive_wrappers::wrappers::{erc20_mintable::ERC20Mintable, i_hyperdrive::IHyperdrive};

    use super::*;

    #[tokio::test]
    async fn test_deploy() -> Result<()> {
        let chain = TestChain::new(None, 1).await?;
        let signer = chain.accounts[0]
            .clone()
            .with_chain_id(chain.chain_id().await?);
        let client = Arc::new(SignerMiddleware::new(chain.provider.clone(), signer));
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
            YieldSpace::get_time_stretch(fixed!(0.05e18)).into()
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
            .initialize(contribution, uint256!(0.05e18), client.address(), true)
            .send()
            .await?;

        Ok(())
    }
}
