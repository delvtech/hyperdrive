use std::env;

use ethers::{signers::LocalWallet, utils::keccak256};

lazy_static! {
    // A set of test accounts.
    pub static ref ALICE: LocalWallet = LocalWallet::from_bytes(&keccak256("alice")).unwrap();
    pub static ref BOB: LocalWallet = LocalWallet::from_bytes(&keccak256("bob")).unwrap();
    pub static ref CELINE: LocalWallet = LocalWallet::from_bytes(&keccak256("celine")).unwrap();

    // The Ethereum URL the tests should connect to. If None, then the tests
    // will spawn an anvil node.
    pub static ref MAYBE_ETHEREUM_URL: Option<String> = env::var("HYPERDRIVE_ETHEREUM_URL").ok().or(None);

    // The amount of fuzz runs that Hyperdrive fuzz tests will use. This is only
    // used by end-to-end fuzz tests that spin up all of the Hyperdrive machinery
    // since lower-level fuzz tests have less constraints.
    pub static ref FUZZ_RUNS: u64 = env::var("HYPERDRIVE_FUZZ_RUNS").ok().map(|s| s.parse().unwrap()).unwrap_or(100);

    // The amount of fuzz runs that fast fuzz tests use.
    pub static ref FAST_FUZZ_RUNS: u64 = env::var("HYPERDRIVE_FAST_FUZZ_RUNS").ok().map(|s| s.parse().unwrap()).unwrap_or(10_000);
}
