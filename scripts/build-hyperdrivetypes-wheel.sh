#!/bin/bash

# Set the python project version to match the hyperdrive version
. scripts/set-hyperdrivetypes-version.sh

# Just in case, check the versions match
. scripts/verify-hyperdrivetypes-version.sh
if [ -z "$HYPERDRIVE_VERSIONS_MATCH" ]; then
  echo "Environment variable HYPERDRIVE_VERSIONS_MATCH is not set. Exiting with failure."
  exit 1
fi

# Build if the versions match
if [ "$HYPERDRIVE_VERSIONS_MATCH" != "true" ]; then
  echo "Version mismatch detected. Exiting with failure."
  exit 1
else
  echo "Versions match. Installing required packages for building the wheel."
  python -m venv --upgrade-deps .venv
  source .venv/bin/activate
  python -m pip install --upgrade pip

  echo "install hyperdrivetypes & test build"
  pip install python/hyperdrivetypes build

  echo "build the wheel for the current platform"
  python -m build --sdist --outdir dist python/hyperdrivetypes
  python -m pip wheel --no-deps --wheel-dir dist python/hyperdrivetypes
fi
