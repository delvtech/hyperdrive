#!/bin/sh

set -e

# Bootstrap the "mainnet_fork" addresses in `deployements.local.json`.
jq '.mainnet | { mainnet_fork: . }' <deployments.json >deployments.local.json
