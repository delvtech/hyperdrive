#!/bin/sh

cat deployments.local.json | jq '.anvil | {
  baseToken: .BASE_TOKEN.address,
  erc4626Hyperdrive: .ERC4626_HYPERDRIVE.address,
  stethHyperdrive: .STETH_HYPERDRIVE.address,
  factory: .FACTORY.address,
  hyperdriveRegistry: .ANVIL_REGISTRY.address,
}' >./artifacts/addresses.json
