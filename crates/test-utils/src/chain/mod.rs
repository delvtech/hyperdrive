mod dev_chain;
mod test_chain;

use std::sync::Arc;

pub use dev_chain::DevChain;
use ethers::{
    middleware::SignerMiddleware,
    providers::{JsonRpcClient, Middleware, Provider},
    signers::{LocalWallet, Signer},
    types::U256,
};
use eyre::Result;
use hyperdrive_addresses::Addresses;
pub use test_chain::TestChain;

#[async_trait::async_trait]
pub trait Chain<T: JsonRpcClient> {
    /// A provider that can access the chain.
    fn provider(&self) -> Provider<T>;

    /// The accounts that are available on the chain.
    fn accounts(&self) -> Vec<LocalWallet>;

    /// The addresses of the Hyperdrive contracts on the chain.
    fn addresses(&self) -> Addresses;

    /// A client that can access the chain.
    async fn client(
        &self,
        signer: LocalWallet,
    ) -> Result<Arc<SignerMiddleware<Provider<T>, LocalWallet>>> {
        Ok(Arc::new(SignerMiddleware::new(
            self.provider(),
            signer.with_chain_id(self.chain_id().await?.low_u32()),
        )))
    }

    /// The chain id.
    async fn chain_id(&self) -> Result<U256> {
        let chain_id = self.provider().get_chainid().await?;
        Ok(chain_id)
    }
}
