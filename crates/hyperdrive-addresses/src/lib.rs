// TODO: To make this more fully featured, this crate should ultimately have:
//
// 1. [ ] A function that gets Hyperdrive addresses by chain id. This is what we
//        can use in prod.

use ethers::types::Address;
use serde::{Deserialize, Serialize};

#[derive(Clone, Default, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[serde(default)]
pub struct Addresses {
    #[serde(alias = "baseToken")]
    #[serde(alias = "base_token_address")]
    pub base_token: Address,
    #[serde(alias = "erc4626Hyperdrive")]
    #[serde(alias = "hyperdrive_address")]
    pub erc4626_hyperdrive: Address,
    #[serde(alias = "stethHyperdrive")]
    pub steth_hyperdrive: Address,
    pub factory: Address,
    #[serde(alias = "hyperdriveRegistry")]
    #[serde(alias = "hyperdrive_registry_address")]
    pub hyperdrive_registry: Address,
}
