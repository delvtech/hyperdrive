// TODO: To make this more fully featured, this crate should ultimately have:
//
// 1. [ ] A function that gets Hyperdrive addresses by chain id. This is what we
//        can use in prod.

use ethers::types::Address;
use serde::{Deserialize, Serialize};

#[derive(Clone, Default, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct Addresses {
    #[serde(rename = "baseToken")]
    pub base: Address,
    #[serde(rename = "mockHyperdrive")]
    pub hyperdrive: Address,
}
