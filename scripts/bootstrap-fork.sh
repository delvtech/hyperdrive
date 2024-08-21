#!/bin/sh

set -e

# Bootstrap the "mainnet_fork" addresses in `deployments.local.json`.
jq '.mainnet | { mainnet_fork: . }' <deployments.json >deployments.local.json
