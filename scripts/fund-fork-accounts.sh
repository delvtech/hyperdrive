#!/bin/sh

set -e

# Ensure that the `NETWORK` variable is defined.
if [[ -z "${NETWORK}" ]]; then
	echo 'Error: $NETWORK must be set'
	exit 1
fi

# Fund default anvil accounts if $ADMIN is not set.
if [[ -z "$ADMIN" ]]; then
  addresses=('0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266' '0x70997970C51812dc3A010C7d01b50e0d17dc79C8' '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC' '0x90F79bf6EB2c4f870365E785982E1f101E93b906' '0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65' '0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc' '0x976EA74026E726554dB657fA54763abd0C3a0aa9' '0x14dC79964da2C08b23698B3D3cc7Ca32193d9955' '0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f' '0xa0Ee7A142d267C1f36714E4a8F75612F20a79720')
else
  addresses=( "$ADMIN" )
fi

# Mint tokens to all of the default anvil accounts.
for address in "${addresses[@]}"
do
  echo "funding ${address}..."

  if [ "$NETWORK" = "mainnet_fork" ]; then
    echo " - funding eth..."
    npx hardhat fork:mint-eth --address "${address}" --network "${NETWORK}" --config "hardhat.config.${NETWORK}.ts"
    echo " - funding dai..."
    npx hardhat fork:mint-dai --address "${address}" --network "${NETWORK}" --config "hardhat.config.${NETWORK}.ts"
    echo " - funding eeth..."
    npx hardhat fork:mint-eeth --address "${address}" --network "${NETWORK}" --config "hardhat.config.${NETWORK}.ts"
    echo " - funding ezeth..."
    npx hardhat fork:mint-ezeth --address "${address}" --network "${NETWORK}" --config "hardhat.config.${NETWORK}.ts"
    echo " - funding reth..."
    npx hardhat fork:mint-reth --address "${address}" --network "${NETWORK}" --config "hardhat.config.${NETWORK}.ts"
    echo " - funding sdai..."
    npx hardhat fork:mint-sdai --address "${address}" --network "${NETWORK}" --config "hardhat.config.${NETWORK}.ts"
    echo " - funding steth..."
    npx hardhat fork:mint-steth --address "${address}" --network "${NETWORK}" --config "hardhat.config.${NETWORK}.ts"
    echo " - funding usde..."
    npx hardhat fork:mint-usde --address "${address}" --network "${NETWORK}" --config "hardhat.config.${NETWORK}.ts"
    echo " - funding wsteth..."
    npx hardhat fork:mint-wsteth --address "${address}" --network "${NETWORK}" --config "hardhat.config.${NETWORK}.ts"
    echo " - funding usdc..."
    npx hardhat fork:mint-usdc --address "${address}" --network "${NETWORK}" --config "hardhat.config.${NETWORK}.ts"
  fi

  if [ "$NETWORK" = "gnosis" ]; then
    echo " - funding xdai..."
    npx hardhat fork:mint-eth --address "${address}" --network "${NETWORK}" --config "hardhat.config.${NETWORK}.ts"
    echo " - funding wsteth..."
    npx hardhat fork:mint-wsteth --address "${address}" --network "${NETWORK}" --config "hardhat.config.${NETWORK}.ts"
    echo " - funding wxdai..."
    npx hardhat fork:mint-wxdai --address "${address}" --network "${NETWORK}" --config "hardhat.config.${NETWORK}.ts"
  fi

done
