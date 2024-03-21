// FIXME: Remove these modules.
mod dev_chain;
mod test_chain;

use std::{sync::Arc, time::Duration};

pub use dev_chain::{DevChain, MNEMONIC};
use ethers::{
    core::utils::Anvil,
    middleware::{
        gas_escalator::{Frequency, GeometricGasPrice},
        GasEscalatorMiddleware, NonceManagerMiddleware, SignerMiddleware,
    },
    providers::{
        Http, HttpClientError, HttpRateLimitRetryPolicy, Middleware, Provider, RetryClient,
        RetryClientBuilder, RetryPolicy,
    },
    signers::Signer,
    types::{Address, U256},
    utils::AnvilInstance,
};
use eyre::Result;
pub use test_chain::{TestChain, TestChainConfig, TestChainWithMocks};

/// A retry policy that will retry on rate limit errors, timeout errors, and
/// "intrinsic gas too high".
#[derive(Debug, Default)]
struct ChainRetryPolicy(HttpRateLimitRetryPolicy);

impl RetryPolicy<HttpClientError> for ChainRetryPolicy {
    fn should_retry(&self, error: &HttpClientError) -> bool {
        self.0.should_retry(error) || error.to_string().contains("intrinsic gas too high")
    }

    fn backoff_hint(&self, error: &HttpClientError) -> Option<Duration> {
        match self.0.backoff_hint(error) {
            Some(duration) => Some(duration),
            None => {
                if error.to_string().contains("intrinsic gas too high") {
                    Some(Duration::from_millis(1))
                } else {
                    None
                }
            }
        }
    }
}

// FIXME: What are the abstractions that I want?
//
// - [ ] There should be an abstraction that makes it easy to get the contract
//       addresses from a DevChain.
// - [ ] There should be an abstraction that makes it easy to spin up an anvil
//       chain.
//    - [ ] It should be possible to forward these logs to a file or in some
//          way surface these logs.
// - [ ] There should be an abstraction that makes it easy to connect to a
//       remote chain or dev chain.
// - [ ] There should be an abstraction that makes it easy to deploy new pools
//       or whole factories given a config.
//
// FIXME: What are some changes that should be made?
//
// - [ ] We should create a deployments module to create new pools and full
//       deployments using the factory.
//    - We need to support deploying pools.
//    - We need to support deploying the factory.
//    - It would be nice to support deploying the full deployment with the
//      factory, the sDAI and Lido deployer coordinators, and two initial pools.
//      That said, instead of doing it like that, I could write the migration
//      script using more orthogonal tools.
pub struct Chain {
    provider: Provider<Http>,
    client_version: String,
    chain_id: u64,
    _maybe_anvil: Option<AnvilInstance>,
}

impl Chain {
    /// Constructs a new `Chain` from an Ethereum RPC URL.
    pub async fn new_with_rpc(rpc_url: String) -> Result<Self> {
        let provider = Provider::<Http>::try_from(rpc_url)?.interval(Duration::from_millis(1));
        let client_version = provider.client_version().await?;
        let chain_id = provider.get_chainid().await?.low_u64();
        Ok(Self {
            provider,
            client_version,
            chain_id,
            _maybe_anvil: None,
        })
    }

    /// Constructs a new `Chain` with a local Anvil chain.
    pub async fn new_with_anvil() -> Result<Self> {
        let anvil = Anvil::new()
            .arg("--timestamp")
            // NOTE: Anvil can't increase the time or set the time of the
            // next block to a time in the past, so we set the genesis block
            // to 12 AM UTC, January 1, 2000 to avoid issues when reproducing
            // old crash reports.
            .arg("946684800")
            .spawn();
        let provider =
            Provider::<Http>::try_from(anvil.endpoint())?.interval(Duration::from_millis(1));
        let client_version = provider.client_version().await?;
        let chain_id = provider.get_chainid().await?.low_u64();
        Ok(Self {
            provider,
            client_version,
            chain_id,
            _maybe_anvil: Some(anvil),
        })
    }
}

impl Chain {
    /// A provider that can access the chain.
    pub fn provider(&self) -> Provider<Arc<RetryClient<Http>>> {
        // Build a provider with a retry policy that will retry on rate limit
        // errors, timeout errors, and "intrinsic gas too high".
        let provider = RetryClientBuilder::default()
            .rate_limit_retries(10)
            .timeout_retries(3)
            .initial_backoff(Duration::from_millis(1))
            .build(
                self.provider.as_ref().clone(),
                Box::<ChainRetryPolicy>::default(),
            );
        Provider::new(Arc::new(provider)).interval(Duration::from_millis(1))
    }

    /// A client that can access the chain.
    pub async fn client<S: Signer + 'static>(
        &self,
        signer: S,
    ) -> Result<
        GasEscalatorMiddleware<
            NonceManagerMiddleware<SignerMiddleware<Provider<Arc<RetryClient<Http>>>, S>>,
        >,
    > {
        // Build a client with signer, nonce management, and gas escalator
        // middleware.
        let client = SignerMiddleware::new_with_provider_chain(self.provider(), signer).await?;
        let address = client.address();
        let client = NonceManagerMiddleware::new(client, address);
        let client = GasEscalatorMiddleware::new(
            client,
            GeometricGasPrice::new(1.125, 10u64, None::<u64>),
            Frequency::PerBlock,
        );

        Ok(client)
    }

    /// Snapshots the chain. This only works for anvil chains.
    pub async fn snapshot(&self) -> Result<U256> {
        if !self.is_anvil() {
            panic!("Can't snapshot a non-anvil chain");
        }
        let id = self.provider.request("evm_snapshot", ()).await?;
        Ok(id)
    }

    /// Reverts the chain to a previous snapshot. This only works for anvil
    /// chains.
    pub async fn revert<U: Into<U256>>(&self, id: U) -> Result<()> {
        if !self.is_anvil() {
            panic!("Can't snapshot a non-anvil chain");
        }
        self.provider
            .request::<[U256; 1], bool>("evm_revert", [id.into()])
            .await?;
        Ok(())
    }

    /// Increases the chains time. This only works for anvil chains.
    pub async fn increase_time(&self, duration: u128) -> Result<()> {
        if !self.is_anvil() {
            panic!("Can't snapshot a non-anvil chain");
        }
        self.provider
            .request::<[u128; 1], i128>("anvil_increaseTime", [duration])
            .await?;
        self.provider
            .request::<[u128; 1], ()>("anvil_mine", [1])
            .await?;
        Ok(())
    }

    /// Sets the accounts balance. This only works for anvil chains.
    pub async fn set_balance<U: Into<U256>>(&self, address: Address, balance: U) -> Result<()> {
        if !self.is_anvil() {
            panic!("Can't snapshot a non-anvil chain");
        }
        self.provider
            .request::<(Address, U256), bool>("anvil_setBalance", (address, balance.into()))
            .await?;
        Ok(())
    }

    /// Checks to see if the underlying chain is an anvil chain.
    fn is_anvil(&self) -> bool {
        Ok(self.client_version.contains("anvil"))
    }
}
