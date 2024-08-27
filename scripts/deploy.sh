#!/bin/sh

set -e

# Ensure that the network variable is defined
if [[ -z "${NETWORK}" ]]; then
  echo 'Error: $NETWORK must be set'
  exit 1
fi

# When deploying to "live" networks, ensure that the repository is equivalent
# to the latest remote tag. This avoids accidentally deploying out-of-date or
# ambiguously versioned contracts.
if [[ "${NETWORK}" != "anvil" && "${NETWORK}" != "hardhat" && "${NETWORK}" != "mainnet_fork" ]]; then
  git remote update
  tag=$(git describe --tags --abbrev=0)
  diff=$(git diff ${tag} --raw -- contracts lib)
  if [[ ! -z "${diff}" ]]; then
    echo "$diff"
    echo "Error: repository contents must match tag ${tag}"
    exit 1
  fi
fi

config_filename="hardhat.config.${NETWORK}.ts"
if [[ "${NETWORK}" == "hardhat" ]]; then
  config_filename="hardhat.config.ts"
fi
npx hardhat deploy:hyperdrive --show-stack-traces --network ${NETWORK} --config "$config_filename"
npx hardhat deploy:verify --show-stack-traces --network ${NETWORK} --config "$config_filename"
