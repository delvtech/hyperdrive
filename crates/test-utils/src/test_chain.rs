use ethers::{
    core::utils::Anvil,
    middleware::SignerMiddleware,
    providers::{Http, Provider},
    signers::{LocalWallet, Signer},
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
use std::{convert::TryFrom, sync::Arc, time::Duration};

/// A local anvil instance with the Hyperdrive contracts deployed.
pub struct TestChain {
    pub provider: Provider<Http>,
    pub addresses: Addresses,
    pub accounts: Vec<LocalWallet>,
    anvil: AnvilInstance,
}

impl TestChain {
    pub async fn new() -> Result<Self> {
        // Deploy an anvil instance and set up a wallet and provider.
        let anvil = Anvil::new().spawn();
        let provider =
            Provider::<Http>::try_from(anvil.endpoint())?.interval(Duration::from_millis(10u64));
        let wallets: Vec<LocalWallet> = anvil.keys().iter().map(|k| k.clone().into()).collect();
        let accounts = wallets
            .iter()
            .map(|w| {
                Arc::new(SignerMiddleware::new(
                    provider.clone(),
                    w.clone().with_chain_id(anvil.chain_id()),
                ))
            })
            .collect::<Vec<_>>();
        let client = accounts[0].clone();

        // Deploy the base token and vault.
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

        Ok(Self {
            addresses: Addresses {
                hyperdrive: erc4626_hyperdrive.address(),
                base: base.address(),
            },
            accounts: anvil.keys().iter().map(|k| k.clone().into()).collect(),
            provider,
            anvil,
        })
    }

    pub fn chain_id(&self) -> u64 {
        self.anvil.chain_id()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ethers::middleware::SignerMiddleware;
    use fixed_point_macros::uint256;
    use hyperdrive_wrappers::wrappers::erc20_mintable::ERC20Mintable;
    use hyperdrive_wrappers::wrappers::i_hyperdrive::IHyperdrive;

    #[tokio::test]
    async fn test_deploy() -> Result<()> {
        let chain = TestChain::new().await?;
        let signer = chain.accounts[0].clone().with_chain_id(chain.chain_id());
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
