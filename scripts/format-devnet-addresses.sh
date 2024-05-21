#!/bin/sh

cat deployments.local.json | jq '.anvil | {
  base_token: .BASE_TOKEN.address,
  erc4626_hyperdrive: .ERC4626_HYPERDRIVE.address,
  steth_hyperdrive: .STETH_HYPERDRIVE.address,
  factory: .FACTORY.address,
  hyperdrive_registry: .ANVIL_REGISTRY.address
}' >./artifacts/addresses.json
