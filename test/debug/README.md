# Debugging

This folder contains a testing utility that can be used to debug Hyperdrive
transactions on the sepolia testnet. The debugging tools rely on an RPC URL
that is provided by the `DEBUG_RPC_URL` environment variable. This tool supports
two different modes:

- Transaction Mode: In this mode, you provide a transaction hash with the
  `TX_HASH` environment variable. The transaction specified by this environment
  variable will be simulated exactly as it was executed. For this to work, the
  `TX_HASH` value must specify a transaction that was mined on the chain
  specified by `DEBUG_RPC_URL`. This mode is preferred for mined transactions.
- Simulation Mode: In this mode, you provide a block height with the `BLOCK`
  environment variable and transaction details including the `FROM` address, the
  `TO` address, the amount of `VALUE` to send, and the `DATA` to send. All of
  these environment variables must be set for this mode to work properly. This
  mode will execute the specified transaction at the specified block height on
  the forked chain. This mode can be used when a transaction hasn't been mined
  or to simulate internal calls.

The environment variables can be put in the `.env` file for convenience or passed
manually. Here is an example of running the script in transaction mode:

```
DEBUG_RPC_URL=http://localhost:8545 TX_HASH=0x278d43d20d134fcfcd92c05d02b33cee1855de8ecae20a3c4ca47e1647e171a7 ./scripts/debug.sh
```

To get more insight into what went wrong (or right) during the transaction
execution, you can add some `console.log` statements in the Hyperdrive codebase
and re-run the tests. Assuming the logs are in the execution path of the debug
transaction, you'll see these logs when you re-run the test.

## Tips

1. To add `console.log` statements, you'll need to import `console2` from
   `forge-std/console2.sol` in each file that you add logs to.
2. You can pretty-print fixed point numbers with the `Lib.toString` function
   from `test/utils/Lib.sol`. You can add `using Lib for *;` on the line after
   the contract declaration to use method syntax like `value.toString(18)`. The
   `18` in this example indicates that the fixed point value has 18 decimals.
3. Start by adding some `console.log` statements to the start of the flow that
   you're calling. You can find the start of the core flows in the following
   files:
   - `HyperdriveLong`: `_openLong`, `_closeLong`
   - `HyperdriveShort`: `_openShort`, `_closeShort`
   - `HyperdriveLP`: `_addLiquidity`, `_removeLiquidity`, `_redeemWithdrawalShares`
   - `HyperdriveCheckpoint`: `_checkpoint`
4. If you want to inspect what happened during `_deposit` or `_withdraw`, you
   may need to add logs to the appropriate `Base` contract for the integration
   that you're using. If you're debugging a stETH yield source, add logs to
   `_depositWithBase`, `_depositWithShares`, or one of the other functions in
   `contracts/src/instances/steth/StETHBase.sol`. Similarly, if you're debugging
   an ERC4626 yield source (like sDAI), you can add logs to the corresponding
   functions in `contracts/src/instances/erc4626/ERC4626Base.sol`.
5. If you want to inspect what happened within the yield source, you can add logs
   to `contracts/test/MockLido.sol` if you're debugging a stETH yield source or
   to `contracts/test/MockERC4626.sol` if you're debugging an ERC4626 yield
   source (like sDAI).
6. If you want to inspect what happened within the base token, you can add logs
   to `contracts/test/ERC20Mintable.sol`. Note that the base token for stETH is
   a placeholder since stETH uses ETH as a base token.
