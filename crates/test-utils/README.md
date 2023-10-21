# test-utils

This crate contains several utilities for working with Hyperdrive instances.
These utilities include a chain abstraction (the `Chain` trait) with
implementations that cover common use-cases for testing and reproducing crashes.
Additionally, these utilities include an `Agent` that connects to a `Chain` and
abstracts away the details of making trades and calculate things like the max
short that can be opened.

## `DevChain`

`DevChain` makes it easy to connect to a Hyperdrive instance running on
[the devnet or testnet](https://github.com/delvtech/hyperdrive). We can connect
to a locally running compose app on the usual ports as follows:

```rust
use test_utils::chain::{Chain, DevChain, MNEMONIC};

#[tokio::test]
async fn test_example() -> Result<()>
    // Connect to an instance of Hyperdrive on a local compose app.
    let chain: Chain = DevChain::new(
        "http://localhost:8545", // the ethereum URL
        "http://localhost:8080", // the artifacts server's URL
        MNEMONIC, // the mnemonic to use when generating accounts
        1 // the number of accounts to fund
    ).await?;

    Ok(())
}
```

## `TestChain`

The ethereum node that `TestChain` connects to is configured by the
`HYPERDRIVE_ETHEREUM_URL` environment variable. If an ethereum URL is provided,
the `TestChain` instance will connect to the specified node. Otherwise, an anvil
node will be spawned that will be killed when the `TestChain` drops out of scope.

`TestChain` can be run in two different modes. The first mode connects to the
specified anvil node and deploys a fresh set of contracts to the chain. This
mode can be used as follows:

```rust
use test_utils::chain::{Chain, TestChain};

#[tokio::test]
async fn test_example() -> Result<()>
    // Get a fresh instance of Hyperdrive.
    let chain: Chain = TestChain::new(
        1 // the number of test accounts to fund
    ).await?;

    Ok(())
}
```

The second mode is more interesting and creates a reproduction environment from
a specified crash report. Crash reports contain an anvil state dump, so the
chain's state will be identical to the state at the time of the crash. The block
timestamp is also replicated. To make it easy to debug, we etch the most
recently deployed compiled smart contracts onto the Hyperdrive instance and
dependency contracts implicated in the crash. This makes it possible to add
arbitrary log statements to get a better understanding of the crash. This mode
can be run as follows:

```rust
use test_utils::chain::{Chain, TestChain};
#[tokio::test]
fn test_example() -> Result<()>
    // Reproduce the chain state at the time of the crash.
    let chain: Chain = TestChain::load_crash(
        "crash_report.json" // the path to the crash report to reproduce
    ).await?;

    Ok(())
}
```

## `Agent`

The following provides an example for how to use the `Agent` to make trades
against a `Chain` instance.

```rust
use fixed_point_macros::fixed;
use test_utils::{
    agent::Agent,
    chain::{Chain, TestChain},
};

#[tokio::test]
fn test_example() -> Result<()>
    // Get a fresh instance of Hyperdrive.
    let chain: Chain = TestChain::new(
        1 // the number of test accounts to fund
    ).await?;

    // Instantiate an agent named Alice.
    let alice = chain.accounts()[0].clone();
    let mut alice = Agent::new(chain.client(alice).await?, chain.addresses().clone(), None).await?;

    // Alice opens a max short.
    alice.open_short(
        alice.get_max_short(None).await?,
        None, // use the default slippage tolerance
    ).await?;

    Ok(())
}
```
