#!/bin/sh

set -e

# Ensure that the `ADMIN` variable is defined.
if [[ -z "${ADMIN}" ]]; then
	echo 'Error: $ADMIN must be set'
	exit 1
fi

# Mint some of each instance's token to the admin address.
npx hardhat fork:mint-eth --address ${ADMIN} --amount 1000 --network mainnet_fork --config hardhat.config.mainnet_fork.ts
npx hardhat fork:mint-steth --address ${ADMIN} --amount 1000 --network mainnet_fork --config hardhat.config.mainnet_fork.ts
npx hardhat fork:mint-reth --address ${ADMIN} --amount 1000 --network mainnet_fork --config hardhat.config.mainnet_fork.ts
npx hardhat fork:mint-dai --address ${ADMIN} --amount 20000 --network mainnet_fork --config hardhat.config.mainnet_fork.ts
npx hardhat fork:mint-sdai --address ${ADMIN} --amount 20000 --network mainnet_fork --config hardhat.config.mainnet_fork.ts

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
  dai14Day: .DAI_14_DAY.address,
  dai30Day: .DAI_30_DAY.address,
  steth14Day: .STETH_14_DAY.address,
  steth30Day: .STETH_30_DAY.address,
  reth14Day: .RETH_14_DAY.address,
  reth30Day: .RETH_30_DAY.address,
  factory: .FACTORY.address,
  hyperdriveRegistry: .["DELV Hyperdrive Registry"].address,
  }' >./artifacts/addresses.json
cp ./deployments.local.json ./artifacts/
