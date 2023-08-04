#!/bin/sh
set -ex

# Execute the devnet smoke test.
forge script script/DevnetSmokeTest.s.sol:DevnetSmokeTest \
   --sender "${ETH_FROM}" \
   --private-key "${PRIVATE_KEY}" \
   --rpc-url "${RPC_URL}" \
   --slow \
   --broadcast
