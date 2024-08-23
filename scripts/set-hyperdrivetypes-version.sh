#!/bin/bash

echo "get hyperdrive version"

# Extract version using sed by reading from the file
HYPERDRIVE_FILE="contracts/src/libraries/Constants.sol"
VERSION=$(sed -n -E 's/.*VERSION = "v([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' "$HYPERDRIVE_FILE")

# Determine the OS using uname and convert to lowercase
OS_TYPE=$(uname | tr '[:upper:]' '[:lower:]')

# Append the version to hyperdrivetypes
HYPERDRIVETYPES_FILE="python/hyperdrivetypes/pyproject.toml"
echo "found version: v$VERSION"
echo "writing to $HYPERDRIVETYPES_FILE"
# Check the operating system to use the correct sed syntax
if [[ "$OSTYPE" == "darwin"* ]]; then
  # e.g. macOS
  sed -i '' -E "s/^(version = \")[0-9]+\.[0-9]+\.[0-9]+(\.*[0-9]*\".*)/\1$VERSION\2/" "$HYPERDRIVETYPES_FILE"
elif [[ "$OSTYPE" == "linux"* ]]; then
  # e.g. Ubuntu
  sed -i -E "s/^(version = \")[0-9]+\.[0-9]+\.[0-9]+(\.*[0-9]*\".*)/\1$VERSION\2/" "$HYPERDRIVETYPES_FILE"
else
  echo "Unsupported OS: $OSTYPE"
  # exit 1
fi
