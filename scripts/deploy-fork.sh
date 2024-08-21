#!/bin/sh

set -e

# Mint some of each instance's token to the admin address.
npx hardhat fork:mint-eth --amount 1000 --network mainnet_fork --config hardhat.config.mainnet_fork.ts
npx hardhat fork:mint-steth --amount 1000 --network mainnet_fork --config hardhat.config.mainnet_fork.ts
npx hardhat fork:mint-reth --amount 1000 --network mainnet_fork --config hardhat.config.mainnet_fork.ts
npx hardhat fork:mint-dai --amount 20000 --network mainnet_fork --config hardhat.config.mainnet_fork.ts
npx hardhat fork:mint-sdai --amount 20000 --network mainnet_fork --config hardhat.config.mainnet_fork.ts

# Bootstrap the "mainnet_fork" addresses in `deployements.local.json`.
jq '.mainnet | { mainnet_fork: . }' <deployments.json >deployments.local.json

# Deploy factory, coordinators, and instances.
npx hardhat deploy:hyperdrive --network mainnet_fork --config hardhat.config.mainnet_fork.ts --show-stack-traces

# Add all deployed instances to the registry.
npx hardhat registry:add --name DAI_14_DAY --value 1 --network mainnet_fork --config hardhat.config.mainnet_fork.ts
npx hardhat registry:add --name DAI_30_DAY --value 1 --network mainnet_fork --config hardhat.config.mainnet_fork.ts
npx hardhat registry:add --name STETH_14_DAY --value 1 --network mainnet_fork --config hardhat.config.mainnet_fork.ts
npx hardhat registry:add --name STETH_30_DAY --value 1 --network mainnet_fork --config hardhat.config.mainnet_fork.ts
npx hardhat registry:add --name RETH_14_DAY --value 1 --network mainnet_fork --config hardhat.config.mainnet_fork.ts
npx hardhat registry:add --name RETH_30_DAY --value 1 --network mainnet_fork --config hardhat.config.mainnet_fork.ts

# Extract the deployed contract addresses to `artifacts/addresses.json`
# for use with the delvtech/infra address server.
cat ./deployments.local.json | jq '.mainnet_fork | {
  hyperdriveRegistry: .["DELV Hyperdrive Registry"].address,
  }' >./artifacts/addresses.json
cp ./deployments.local.json ./artifacts/
