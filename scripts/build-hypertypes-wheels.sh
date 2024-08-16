#!/bin/bash

# hypertypes install

echo "install required packages for building wheels"
python -m pip install --upgrade pip
python -m venv --upgrade-deps .venv
source .venv/bin/activate
cd python/hypertypes && pip install '.[all]' build

echo "build the wheel for the current platform"
python -m build