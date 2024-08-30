#!/bin/bash

# Extract version from hyperdrive
constants_file="contracts/src/libraries/Constants.sol"
VERSION_CONSTANTS=$(sed -n -E 's/.*VERSION = "v([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' "$constants_file")

# Extract version from hyperdrivetypes
init_file="python/hyperdrivetypes/pyproject.toml"
VERSION_INIT=$(sed -n -E 's/version = "([0-9]+\.[0-9]+\.[0-9]+)\.*[0-9]*".*/\1/p' "$init_file")

# Compare versions
if [ "$VERSION_CONSTANTS" == "$VERSION_INIT" ]; then
  echo "versions match!"
  echo "hyperdrive version: $VERSION_CONSTANTS"
  echo "hyperdrivetypes version: $VERSION_INIT"
  export HYPERDRIVE_VERSIONS_MATCH=true
else
  echo "versions do not match!"
  echo "hyperdrive version: $VERSION_CONSTANTS"
  echo "hyperdrivetypes version: $VERSION_INIT"
  export HYPERDRIVE_VERSIONS_MATCH=false
fi
