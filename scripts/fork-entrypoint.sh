#!/bin/sh

set -e

# When a user hits `ctrl+c` or another interrupt, kill all background processes as well.
trap 'kill $(jobs -p) 2>/dev/null' EXIT

# Run anvil chain as a background process.
anvil --fork-url ${MAINNET_RPC_URL} --chain-id 42069 &
ANVIL=$!

# Deploy the contract to anvil.
scripts/deploy-fork.sh

# Don't exit unless anvil errors out.
wait $ANVIL
