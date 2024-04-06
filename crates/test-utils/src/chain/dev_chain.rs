use std::time::Duration;

use ethers::{
    providers::{Http, Provider},
    signers::{coins_bip39::English, LocalWallet, MnemonicBuilder, Signer},
};
use eyre::{eyre, Result};
use fixed_point_macros::uint256;
use hyperdrive_addresses::Addresses;
use tokio::time::sleep;

use super::Chain;

pub const MNEMONIC: &str =
    "shed present manage school gym spatial sure put tongue dragon left bless share chair element";

const RETRIES: usize = 5;
const RETRY_TIME: Duration = Duration::from_millis(500);

/// A local anvil instance with the Hyperdrive contracts deployed.
pub struct DevChain {
    provider: Provider<Http>,
    addresses: Addresses,
    accounts: Vec<LocalWallet>,
}

#[async_trait::async_trait]
impl Chain for DevChain {
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

impl DevChain {
    /// Given the ethereum URL and the artifacts URL of a devnet, this creates
    /// a new DevChain instance with a set of funded accounts on the devnet.
    pub async fn new(
        ethereum_url: &str,
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
        let provider = Provider::try_from(ethereum_url)?.interval(Duration::from_millis(10));
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
            provider,
            addresses,
            accounts,
        })
    }
}
