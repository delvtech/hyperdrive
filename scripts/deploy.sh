#!/bin/sh

set -e

# Ensure that the network variable is defined
if [[ -z "${NETWORK}" ]]; then
  echo 'Error: $NETWORK must be set'
  exit 1
fi

# Deploy and verify any contracts in the network config specified by `NETWORK`
# that haven't already been deployed and verified.
config_filename="hardhat.config.${NETWORK}.ts"
if [[ "${NETWORK}" == "hardhat" ]]; then
  config_filename="hardhat.config.ts"
fi
npx hardhat deploy:hyperdrive --show-stack-traces --network ${NETWORK} --config "$config_filename"
# npx hardhat deploy:verify --show-stack-traces --network ${NETWORK} --config "$config_filename"
