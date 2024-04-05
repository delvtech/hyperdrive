mod deploy;
mod etch;
mod test_chain;

use std::{sync::Arc, time::Duration};

use async_trait::async_trait;
pub use deploy::TestChainConfig;
use ethers::{
    core::utils::Anvil,
    middleware::{
        gas_escalator::{Frequency, GeometricGasPrice},
        nonce_manager::NonceManagerError,
        GasEscalatorMiddleware, MiddlewareError, NonceManagerMiddleware, SignerMiddleware,
    },
    providers::{
        Http, HttpClientError, HttpRateLimitRetryPolicy, Middleware, PendingTransaction, Provider,
        RetryClient, RetryClientBuilder, RetryPolicy,
    },
    signers::Signer,
    types::{transaction::eip2718::TypedTransaction, Address, BlockId, U256},
    utils::AnvilInstance,
};
use eyre::Result;
pub use test_chain::TestChain;

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

type ChainClientProvider = Arc<RetryClient<Http>>;

type ChainClientInner<S> = NonceManagerMiddleware<
    SignerMiddleware<GasEscalatorMiddleware<Provider<Arc<RetryClient<Http>>>>, S>,
>;

#[derive(Debug)]
pub struct ChainClient<S: Signer + 'static> {
    inner: NonceManagerMiddleware<
        SignerMiddleware<GasEscalatorMiddleware<Provider<Arc<RetryClient<Http>>>>, S>,
    >,
    address: Address,
}

/// A client with a provider stack that includes a retry policy, nonce manager,
/// signer, and gas escalator.
impl<S: Signer + 'static> ChainClient<S> {
    pub async fn new(provider: Provider<Http>, signer: S) -> Result<Self> {
        // Build a provider with a retry policy that will retry on rate limit
        // errors, timeout errors, and "intrinsic gas too high".
        let provider = RetryClientBuilder::default()
            .rate_limit_retries(10)
            .timeout_retries(3)
            .initial_backoff(Duration::from_millis(1))
            .build(
                provider.as_ref().clone(),
                Box::<ChainRetryPolicy>::default(),
            );
        let provider = Provider::new(Arc::new(provider)).interval(Duration::from_millis(1));

        // Build a client with signer, nonce management, and gas escalator
        // middleware.
        let inner = GasEscalatorMiddleware::new(
            provider,
            GeometricGasPrice::new(1.125, 10u64, None::<u64>),
            Frequency::PerBlock,
        );
        let inner = SignerMiddleware::new_with_provider_chain(inner, signer).await?;
        let address = inner.address();
        let inner = NonceManagerMiddleware::new(inner, address);

        Ok(Self { inner, address })
    }

    /// Gets the client's address.
    pub fn address(&self) -> Address {
        self.address
    }
}

#[cfg_attr(target_arch = "wasm32", async_trait(?Send))]
#[cfg_attr(not(target_arch = "wasm32"), async_trait)]
impl<S: Signer + 'static> Middleware for ChainClient<S> {
    // NOTE: This is a pass-through middleware implementation, so we just use
    // the error from the top of the middleware stack.
    type Error = NonceManagerError<Self::Inner>;

    type Provider = ChainClientProvider;
    type Inner = ChainClientInner<S>;

    fn inner(&self) -> &Self::Inner {
        &self.inner
    }

    async fn send_transaction<T: Into<TypedTransaction> + Send + Sync>(
        &self,
        tx: T,
        block: Option<BlockId>,
    ) -> Result<PendingTransaction<'_, Self::Provider>, Self::Error> {
        Ok(self
            .inner
            .send_transaction(tx, block)
            .await
            .map_err(MiddlewareError::from_err)?)
    }
}

/// An abstraction over Ethereum chains that provides convenience methods for
/// constructing providers and clients with useful middleware. Additionally, it
/// provides methods for interacting with the chain that are specific to anvil
/// chains.
pub struct Chain {
    provider: Provider<Http>,
    client_version: String,
    _maybe_anvil: Option<AnvilInstance>,
}

impl Chain {
    /// Constructs a new `Chain` from an Ethereum RPC URL. If the RPC URL is
    /// excluded, a local anvil node is spun up.
    pub async fn connect(maybe_rpc_url: Option<String>) -> Result<Self> {
        if let Some(rpc_url) = maybe_rpc_url {
            let provider = Provider::<Http>::try_from(rpc_url)?.interval(Duration::from_millis(1));
            let client_version = provider.client_version().await?;
            Ok(Self {
                provider,
                client_version,
                _maybe_anvil: None,
            })
        } else {
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
            Ok(Self {
                provider,
                client_version,
                _maybe_anvil: Some(anvil),
            })
        }
    }
}

impl Chain {
    /// A provider that can access the chain.
    pub fn provider(&self) -> Provider<Http> {
        self.provider.clone()
    }

    /// A client that can access the chain.
    pub async fn client<S: Signer + 'static>(&self, signer: S) -> Result<Arc<ChainClient<S>>> {
        Ok(Arc::new(ChainClient::new(self.provider(), signer).await?))
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

    /// Mints a ether to an address. This only works for anvil chains.
    pub async fn deal<U: Into<U256>>(&self, address: Address, amount: U) -> Result<()> {
        if !self.is_anvil() {
            panic!("Can't snapshot a non-anvil chain");
        }
        let balance = self.provider.get_balance(address, None).await?;
        self.provider
            .request::<(Address, U256), ()>(
                "anvil_setBalance",
                (address, U256::from(balance) + amount),
            )
            .await?;
        Ok(())
    }

    /// Checks to see if the underlying chain is an anvil chain.
    fn is_anvil(&self) -> bool {
        self.client_version.contains("anvil")
    }
}
