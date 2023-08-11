use std::{convert::TryFrom, time::Duration};

use ethers::{
    providers::{Http, Middleware, Provider},
    signers::{coins_bip39::English, LocalWallet, MnemonicBuilder, Signer},
};
use eyre::{eyre, Result};
use fixed_point_macros::uint256;
use hyperdrive_addresses::Addresses;
use tokio::time::sleep;

pub const MNEMONIC: &str = "test test test test test test test test test test test test";

const RETRIES: usize = 5;
const RETRY_TIME: Duration = Duration::from_millis(500);

/// A local anvil instance with the Hyperdrive contracts deployed.
pub struct DevChain {
    pub provider: Provider<Http>,
    pub addresses: Addresses,
    pub accounts: Vec<LocalWallet>,
}

impl DevChain {
    /// Given the ethereum URL and the artifacts URL of a devnet, this creates
    /// a new DevChain instance with a set of funded accounts on the devnet.
    pub async fn new(
        eth_url: &str,
        artifacts_url: &str,
        mnemonic: &str,
        num_accounts: usize,
    ) -> Result<Self> {
        // Poll the artifacts server for the hyperdrive addresses.
        let mut maybe_addresses = None;
        for _ in 0..RETRIES {
            let response = reqwest::get(artifacts_url).await?;
            if response.status().is_success() {
                maybe_addresses = Some(response.json::<Addresses>().await?);
                break;
            } else {
                sleep(RETRY_TIME).await;
            }
        }
        let addresses = maybe_addresses.ok_or(eyre!(
            "couldn't get hyperdrive addresses after {} retries",
            RETRIES
        ))?;

        // Generate some accounts from the provided mnemonic.
        let provider = Provider::try_from(eth_url)?;
        let mut accounts = vec![];
        let mut builder = MnemonicBuilder::<English>::default().phrase(mnemonic);
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

        Ok(Self {
            provider: Provider::try_from(eth_url)?,
            addresses,
            accounts,
        })
    }

    pub async fn chain_id(&self) -> Result<u64> {
        self.provider
            .get_chainid()
            .await
            .map(|id| id.as_u64())
            .or(Err(eyre!("couldn't get chain id")))
    }
}
