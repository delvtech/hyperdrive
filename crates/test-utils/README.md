# test-utils

This crate contains several utilities for working with Hyperdrive instances.
These utilities include a chain abstraction (the `Chain` trait) with
implementations that cover common use-cases for testing and reproducing crashes.
Additionally, these utilities include an `Agent` that connects to a `Chain` and
abstracts away the details of making trades and calculate things like the max
short that can be opened.

The following sections explain the purpose of the tools at a high-level and
come with a corresponding example. You can run the examples with the command:

```bash
cargo run --example $EXAMPLE_NAME
```

## `DevChain`

`DevChain` makes it easy to connect to a Hyperdrive instance running on
[the devnet or testnet](https://github.com/delvtech/infra). Check out[this
example](examples/dev_chain.rs) for some sample code. You can run this example
with the command:

```bash
cargo run --example dev_chain
```

## `TestChain`

The ethereum node that `TestChain` connects to is configured by the
`HYPERDRIVE_ETHEREUM_URL` environment variable. If an ethereum URL is provided,
the `TestChain` instance will connect to the specified node. Otherwise, an anvil
node will be spawned that will be killed when the `TestChain` drops out of scope.

`TestChain` can be run in two different modes. The first mode connects to the
specified anvil node and deploys a fresh set of contracts to the chain. Check
out [this example](examples/test_chain_new.rs) for some sample code. You can run
this example with the command:

```bash
cargo run --example test_chain_new
```

The second mode is more interesting and creates a reproduction environment from
a specified crash report. Crash reports contain an anvil state dump, so the
chain's state will be identical to the state at the time of the crash. The block
timestamp is also replicated. To make it easy to debug, we etch the most
recently compiled smart contracts onto the Hyperdrive instance and dependency
contracts implicated in the crash. This makes it possible to add arbitrary log
statements to get a better understanding of the crash. Check out
[this example](examples/test_chain_load_crash.rs) for some sample code. You can
run this example with the command:

```bash
cargo run --example test_chain_load_crash
```

If you want to connect to a local anvil node to collect logs, you'll want to
spawn the node with options like:

```
anvil --code-size-limit 100000 --timestamp 0
```

to ensure that you don't have issues with the crash timestamp occurring before
the anvil genesis block.

## `Agent`

`Agent` abstracts away the details of trading on Hyperdrive and provides several
helpers to calculate the max trades that traders can open given their budgets
and the current market conditions. Check out
[this example](examples/max_short.rs) for some sample code. You can run this
example with the command:

```bash
cargo run --example max_short
```

# Scripts

Along with the test utilities, this crate also contains scripts for interacting
with live versions of the protocol. In order to make use of these scripts, add
the following fields to your root level `.env` file:

```bash
HYPERDRIVE_ETHEREUM_URL=
HYPERDRIVE_ARTIFACTS_URL=
HYPERDRIVE_PRIVATE_KEY=
```

These variables will be overwritten by variables already present in the
environment which makes it easy to use alternate variables as follows:

```bash
ENVVAR=ENVVAR_VALUE cargo run --bin SCRIPT
```

## Pause

The `pause` script pauses the Hyperdrive pool, which puts the pool into a state
where `openLong`, `openShort`, and `addLiquidity` are disabled. For competition
pools, only the admin can call `pause`, so make sure that you are using the
correct private key in your environment. You can run the `pause` script with the
command:

```bash
cargo run --bin pause
```
