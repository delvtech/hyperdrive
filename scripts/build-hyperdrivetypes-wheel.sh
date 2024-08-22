#!/bin/bash

# hyperdrivetypes install

echo "install required packages for building wheels"
python -m venv --upgrade-deps .venv
source .venv/bin/activate
python -m pip install --upgrade pip

echo "install hyperdrivetypes & test build"
pip install python/hyperdrivetypes build

echo "build the wheel for the current platform"
python -m build --sdist --outdir dist python/hyperdrivetypes
python -m pip wheel --no-deps --wheel-dir dist python/hyperdrivetypes