// TODO: To make this more fully featured, this crate should ultimately have:
//
// 1. [ ] A function that gets the Hyperdrive addresses from an artifacts server.
// 2. [ ] A function that gets Hyperdrive addresses by chain id. This is what we
//        can use in prod.

use ethers::types::Address;

#[derive(Default, Debug, Eq, PartialEq, Clone)]
pub struct Addresses {
    pub base: Address,
    pub hyperdrive: Address,
}
