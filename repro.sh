#!/bin/sh
set -ex

# Generate the repro test suite.
forge script script/DevnetRepro.s.sol:DevnetRepro \
   --rpc-url "${RPC_URL}" \
   --slow \
   --broadcast
