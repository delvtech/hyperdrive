#!/bin/sh

set -e

# When a user hits `ctrl+c` or another interrupt, kill all background processes as well.
trap 'kill $(jobs -p) 2>/dev/null' EXIT

anvil --fork-url ${MAINNET_RPC_URL} --chain-id 42069 &

sleep 5
# PERF: The deploy step comprises ~90% of cached build time due to a solc download
# on the first compiler run. Running `npx hardhat compile` in the node-builder stage
# would fix the issue, but also require defining all build args in that stage
# as well as defining them without defaults in this stage 🤮.
scripts/deploy-fork.sh
cat ./deployments.local.json | jq ".mainnet_fork | {
  dai14Day: .DAI_14_DAY.address,
  dai30Day: .DAI_30_DAY.address,
  steth14Day: .STETH_14_DAY.address,
  steth30Day: .STETH_30_DAY.address,
  reth14Day: .RETH_14_DAY.address,
  reth30Day: .RETH_30_DAY.address,
  factory: .FACTORY.address,
  hyperdriveRegistry: .MAINNET_FORK_REGISTRY.address,
  }" >./artifacts/addresses.json
