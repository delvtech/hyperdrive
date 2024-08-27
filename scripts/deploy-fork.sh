#!/bin/sh

set -e

# Ensure that the NETWORK variable is defined.
if [[ -z "$NETWORK" ]]; then
  echo 'Error: $NETWORK must be set'
  exit 1
fi

# Ensure that the ADMIN variable is defined.
if [[ -z "$ADMIN" ]]; then
  echo 'Error: $ADMIN must be set'
  exit 1
fi

# Mint some of each instance's token to the deployer address.
sh scripts/fund-fork-accounts.sh

# Deploy factory, coordinators, and instances.
npx hardhat deploy:hyperdrive --network $NETWORK --config hardhat.config.$NETWORK.ts --show-stack-traces

# Extract the deployed contract addresses to `artifacts/addresses.json`
# for use with the delvtech/infra address server.
if [ "$NETWORK" == "mainnet_fork" ]; then
  cat ./deployments.local.json | jq ".mainnet_fork | {
   hyperdriveRegistry: .[\"DELV Hyperdrive Registry\"].address,
   }" >./artifacts/addresses.json
  cp ./deployments.local.json ./artifacts/
else
  cat ./deployments.json | jq ".$NETWORK |  {
   hyperdriveRegistry: .[\"DELV Hyperdrive Registry\"].address,
   }" >./artifacts/addresses.json
  cp ./deployments.json ./artifacts/
fi
