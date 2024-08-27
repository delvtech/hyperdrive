#!/bin/sh

set -e

# Mint some of each instance's token to the deployer address.
sh scripts/fund-fork-accounts.sh

# Deploy factory, coordinators, and instances.
npx hardhat deploy:hyperdrive --network mainnet_fork --config hardhat.config.mainnet_fork.ts --show-stack-traces

# Extract the deployed contract addresses to `artifacts/addresses.json`
# for use with the delvtech/infra address server.
if ["$NETWORK" == "mainnet_fork"]; then
  cat ./deployments.local.json | jq ".mainnet_fork | {
   hyperdriveRegistry: .["DELV Hyperdrive Registry"].address,
   }" >./artifacts/addresses.json
  cp ./deployments.local.json ./artifacts/
else
  cat ./deployments.json | jq ".$NETWORK |  {
   hyperdriveRegistry: .["DELV Hyperdrive Registry"].address,
   }" >./artifacts/addresses.json
  cp ./deployments.json ./artifacts/
fi
