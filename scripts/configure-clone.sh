#!/bin/sh

set -e

# Mint tokens to all of the default anvil accounts.
set -- '0x042CAb2Ea353fC48C9491bDbF10a12Cfe9072B6C' '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266' '0x70997970C51812dc3A010C7d01b50e0d17dc79C8' '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC' '0x90F79bf6EB2c4f870365E785982E1f101E93b906' '0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65' '0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc' '0x976EA74026E726554dB657fA54763abd0C3a0aa9' '0x14dC79964da2C08b23698B3D3cc7Ca32193d9955' '0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f' '0xa0Ee7A142d267C1f36714E4a8F75612F20a79720' '0x004dfC2dBA6573fa4dFb1E86e3723e1070C0CfdE' '0x005182C62DA59Ff202D53d6E42Cef6585eBF9617' '0x005BB73FddB8CE049eE366b50d2f48763E9Dc0De' '0x0065291E64E40FF740aE833BE2F68F536A742b70' '0x0076b154e60BF0E9088FcebAAbd4A778deC5ce2c' '0x00860d89A40a5B4835a3d498fC1052De04996de6' '0x00905A77Dc202e618d15d1a04Bc340820F99d7C4' '0x009ef846DcbaA903464635B0dF2574CBEE66caDd' '0x00D5E029aFCE62738fa01EdCA21c9A4bAeabd434' '0x020A6F562884395A7dA2be0b607Bf824546699e2' '0x020a898437E9c9DCdF3c2ffdDB94E759C0DAdFB6' '0x020b42c1E3665d14275E2823bCef737015c7f787' '0x02147558D39cE51e19de3A2E1e5b7c8ff2778829' '0x021f1Bbd2Ec870FB150bBCAdaaA1F85DFd72407C' '0x02237E07b7Ac07A17E1bdEc720722cb568f22840' '0x022ca016Dc7af612e9A8c5c0e344585De53E9667' '0x0235037B42b4c0575c2575D50D700dD558098b78'
for address in "$@"; do
  echo "funding ${address}..."
  echo " - funding ${address} eth..."
  npx hardhat fork:mint-eth --address ${address} --amount 1000 --network clone --config hardhat.config.clone.ts
  echo " - funding ${address} steth..."
  npx hardhat fork:mint-steth --address ${address} --amount 1000 --network clone --config hardhat.config.clone.ts
  echo " - funding ${address} reth..."
  npx hardhat fork:mint-dai --address ${address} --amount 20000 --network clone --config hardhat.config.clone.ts
  echo " - funding ${address} sdai..."
  npx hardhat fork:mint-sdai --address ${address} --amount 20000 --network clone --config hardhat.config.clone.ts
done

# Extract the deployed mainnet contract addresses to `artifacts/addresses.json`
# for use with the delvtech/infra address server.
cat ./deployments.json | jq '.mainnet | {
  hyperdriveRegistry: .["DELV Hyperdrive Registry"].address
  }' >./artifacts/addresses.json

# Copy the deployed mainnet contracts to the 'clone' network section in the `deployments.local.json` file.
combined=$(jq -s '{"clone": .[0].mainnet} * .[1] | .' deployments.json deployments.local.json)
echo $combined >deployments.local.json
