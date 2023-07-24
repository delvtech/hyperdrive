#!/bin/sh
set -ex

# Sleep for a few seconds to allow the Ethereum service to start up.
sleep 2

# Execute the devnet smoke test.
forge script script/DevnetSmokeTest.s.sol:DevnetSmokeTest \
   --sender "${ETH_FROM}" \
   --private-key "${PRIVATE_KEY}" \
   --rpc-url "${RPC_URL}" \
   --slow \
   --broadcast
