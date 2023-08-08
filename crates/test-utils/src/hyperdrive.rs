use ethers::signers::Signer;
use ethers::{
    core::utils::Anvil,
    middleware::SignerMiddleware,
    providers::{Http, Provider},
    signers::LocalWallet,
    types::{Address, H256, U256},
    utils::AnvilInstance,
};
use eyre::Result;
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, uint256};
use hyperdrive_wrappers::wrappers::{
    erc20_mintable::ERC20Mintable,
    erc4626_data_provider::ERC4626DataProvider,
    erc4626_hyperdrive::ERC4626Hyperdrive,
    i_hyperdrive::{Fees, IHyperdrive, PoolConfig},
    mock4626::Mock4626,
};
use std::{convert::TryFrom, sync::Arc, time::Duration};

#[derive(Clone)]
pub struct Hyperdrive {
    pub hyperdrive: IHyperdrive<SignerMiddleware<Provider<Http>, LocalWallet>>,
    pub base: ERC20Mintable<SignerMiddleware<Provider<Http>, LocalWallet>>,
    pub accounts: Vec<Arc<SignerMiddleware<Provider<Http>, LocalWallet>>>,
    _anvil: Arc<AnvilInstance>, // NOTE: Drop this when Hyperdrive is dropped.
}

impl Hyperdrive {
    /// Creates a new Hyperdrive instance.
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
            time_stretch: Hyperdrive::get_time_stretch(fixed!(0.05e18)).into(), // time stretch for 5% rate
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

        Ok(Hyperdrive {
            hyperdrive: IHyperdrive::new(erc4626_hyperdrive.address(), client.clone()),
            base,
            accounts,
            _anvil: Arc::new(anvil),
        })
    }

    fn get_time_stretch(mut rate: FixedPoint) -> FixedPoint {
        rate = (U256::from(rate) * uint256!(100)).into();
        let time_stretch = fixed!(5.24592e18) / (fixed!(0.04665e18) * rate);
        fixed!(1e18) / time_stretch
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_deploy() -> Result<()> {
        let deployment = Hyperdrive::new().await?;
        let hyperdrive = &deployment.hyperdrive;
        let base = &deployment.base;
        let alice = deployment.accounts.first().unwrap();

        // Verify that the Hyperdrive address is non-zero.
        assert_ne!(hyperdrive.address(), Address::zero());

        // Ensure that the pool config isn't equal to the empty config.
        let config = hyperdrive.get_pool_config().call().await?;
        assert_ne!(config, PoolConfig::default());

        // Mint some base and approve the Hyperdrive instance.
        let contribution = uint256!(1_000_000e18);
        base.mint(contribution).send().await?;
        base.approve(hyperdrive.address(), U256::MAX).send().await?;

        // Initialize the pool.
        let rate = uint256!(0.05e18);
        hyperdrive
            .initialize(contribution, rate, alice.address(), true)
            .send()
            .await?;
        let lp_shares = hyperdrive
            .balance_of(U256::zero(), alice.address())
            .call()
            .await?;
        assert_eq!(
            lp_shares,
            contribution - config.minimum_share_reserves * U256::from(2)
        );

        Ok(())
    }
}
