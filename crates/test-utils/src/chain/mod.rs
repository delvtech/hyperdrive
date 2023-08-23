mod dev_chain;
mod test_chain;

use std::{sync::Arc, time::Duration};

pub use dev_chain::DevChain;
use ethers::{
    middleware::SignerMiddleware,
    providers::{
        Http, HttpClientError, HttpRateLimitRetryPolicy, Middleware, Provider, RetryClient,
        RetryClientBuilder, RetryPolicy,
    },
    signers::{LocalWallet, Signer},
    types::U256,
};
use eyre::Result;
use hyperdrive_addresses::Addresses;
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

pub type ChainClient = SignerMiddleware<Provider<Arc<RetryClient<Http>>>, LocalWallet>;

#[async_trait::async_trait]
pub trait Chain {
    /// A provider that can access the chain.
    fn provider(&self) -> Provider<Http>;

    /// The accounts that are available on the chain.
    fn accounts(&self) -> Vec<LocalWallet>;

    /// The addresses of the Hyperdrive contracts on the chain.
    fn addresses(&self) -> Addresses;

    /// A client that can access the chain.
    async fn client(&self, signer: LocalWallet) -> Result<Arc<ChainClient>> {
        // Build a client with a retry policy that will retry on rate limit
        // errors, timeout errors, and "intrinsic gas too high".
        let provider = RetryClientBuilder::default()
            .rate_limit_retries(10)
            .timeout_retries(3)
            .initial_backoff(Duration::from_millis(1))
            .build(
                self.provider().as_ref().clone(),
                Box::<ChainRetryPolicy>::default(),
            );
        let provider = Provider::new(Arc::new(provider)).interval(Duration::from_millis(1));

        Ok(Arc::new(SignerMiddleware::new(
            provider,
            signer.with_chain_id(self.chain_id().await?.low_u64()),
        )))
    }

    /// The chain id.
    async fn chain_id(&self) -> Result<U256> {
        let chain_id = self.provider().get_chainid().await?;
        Ok(chain_id)
    }
}
