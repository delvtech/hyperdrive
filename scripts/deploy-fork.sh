#!/bin/sh

set -e

# Ensure that the `ADMIN` variable is defined.
if [[ -z "${ADMIN}" ]]; then
	echo 'Error: $NETWORK must be set'
	exit 1
fi


addresses=(${ADMIN} 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC 0x90F79bf6EB2c4f870365E785982E1f101E93b906 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc 0x976EA74026E726554dB657fA54763abd0C3a0aa9 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955 0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720)
for address in addresses; do
  # Mint some of each instance's token to the admin address.
  npx hardhat fork:mint-eth --address ${address} --amount 1000 --network mainnet_fork --config hardhat.config.mainnet_fork.ts
  npx hardhat fork:mint-steth --address ${address} --amount 1000 --network mainnet_fork --config hardhat.config.mainnet_fork.ts
  npx hardhat fork:mint-reth --address ${address} --amount 1000 --network mainnet_fork --config hardhat.config.mainnet_fork.ts
  npx hardhat fork:mint-dai --address ${address} --amount 20000 --network mainnet_fork --config hardhat.config.mainnet_fork.ts
  npx hardhat fork:mint-sdai --address ${address} --amount 20000 --network mainnet_fork --config hardhat.config.mainnet_fork.ts
done

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
