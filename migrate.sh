#!/bin/sh
set -ex

# Create an artifacts directory if it doesn't already exist.
mkdir -p ./artifacts

# Execute the devnet migration.
forge script script/DevnetMigration.s.sol:DevnetMigration \
   --sender "${ETH_FROM}" \
   --private-key "${PRIVATE_KEY}" \
   --rpc-url "${RPC_URL}" \
   --code-size-limit 9999999999 \
   --slow \
   --broadcast

# Move the addresses file to the correct location. We wait to do this since
# the addresses are written during the simulation phase, and we want to use
# the addresses file as a signal that the contracts have been successfully
# migrated.
mv ./artifacts/script_addresses.json ./artifacts/addresses.json
