#!/bin/sh

set -ex

# Sleep for a few seconds to allow the Ethereum service to start up.
sleep 2

# Run the migrations script.
FOUNDRY_PROFILE="production" forge script script/MockHyperdrive.s.sol \
   --sender "${ETH_FROM}" \
   --private-key "${PRIVATE_KEY}" \
   --rpc-url "${RPC_URL}" \
   --slow \
   --broadcast

# Move the addresses file to the correct location. We wait to do this since
# the addresses are written during the simulation phase, and we want to use
# the addresses file as a signal that the contracts have been successfully
# migrated.
mv ./artifacts/script_addresses.json ./artifacts/addresses.json
