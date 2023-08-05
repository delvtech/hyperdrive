use crate::fixed_point::FixedPoint;
use crate::generated::{
    erc20_mintable::ERC20Mintable,
    erc4626_data_provider::ERC4626DataProvider,
    erc4626_hyperdrive::ERC4626Hyperdrive,
    ihyperdrive::{Fees, IHyperdrive, PoolConfig},
    mock4626::Mock4626,
};
use ethers::signers::Signer;
use ethers::{
    core::utils::Anvil,
    middleware::SignerMiddleware,
    providers::{Http, Provider},
    signers::LocalWallet,
    types::{Address, H256, U256},
    utils::{parse_units, AnvilInstance},
};
use eyre::Result;
use std::{convert::TryFrom, sync::Arc, time::Duration};

pub struct Hyperdrive {
    pub hyperdrive: IHyperdrive<SignerMiddleware<Provider<Http>, LocalWallet>>,
    pub base: ERC20Mintable<SignerMiddleware<Provider<Http>, LocalWallet>>,
    pub accounts: Vec<Arc<SignerMiddleware<Provider<Http>, LocalWallet>>>,
    _anvil: AnvilInstance, // NOTE: Drop this when Hyperdrive is dropped.
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
            initial_share_price: parse_units("1", 18)?.into(),
            minimum_share_reserves: parse_units("10", 18)?.into(),
            position_duration: U256::from(60 * 60 * 24 * 365), // 1 year
            checkpoint_duration: U256::from(60 * 60 * 24),     // 1 day
            time_stretch: Hyperdrive::get_time_stretch(parse_units("0.05", 18).unwrap().into())
                .into(), // time stretch for 5% rate
            governance: client.address(),
            fee_collector: client.address(),
            fees: Fees {
                curve: parse_units("0.05", 18)?.into(),
                flat: parse_units("0.0005", 18)?.into(),
                governance: parse_units("0.15", 18)?.into(),
            },
            oracle_size: U256::from(10),
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
            _anvil: anvil,
        })
    }

    fn get_time_stretch(mut rate: FixedPoint) -> FixedPoint {
        rate = (U256::from(rate) * U256::from(100)).into();
        let time_stretch = FixedPoint::from(parse_units("5.24592", 18).unwrap())
            / (FixedPoint::from(parse_units("0.04665", 18).unwrap()) * rate);
        return FixedPoint::one() / time_stretch;
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
        let contribution = U256::from(parse_units("1_000_000", 18)?);
        base.mint(contribution).send().await?;
        base.approve(hyperdrive.address(), U256::MAX).send().await?;

        // Initialize the pool.
        let rate = U256::from(parse_units("0.05", 18)?);
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
