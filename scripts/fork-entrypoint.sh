#!/bin/sh

set -e

# When a user hits `ctrl+c` or another interrupt, kill all background processes as well.
trap 'kill $(jobs -p) 2>/dev/null' EXIT

# Run anvil chain as a background process.
anvil --fork-url ${MAINNET_RPC_URL} --chain-id 42069 &

# Deploy the contract to anvil.
scripts/deploy-fork.sh

# Output the deployed addresses in a `delvtech/hyperdrive-infra` address server compatible format.
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
cp ./deployments.local.json ./artifacts/
