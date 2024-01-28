[![Tests](https://github.com/delvtech/hyperdrive/actions/workflows/solidity_test.yml/badge.svg)](https://github.com/delvtech/hyperdrive/actions/workflows/solidity_test.yml)
[![Coverage](https://coveralls.io/repos/github/delvtech/hyperdrive/badge.svg?branch=main&t=vnW3xG&kill_cache=1&service=github)](https://coveralls.io/github/delvtech/hyperdrive?branch=main)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://github.com/delvtech/elf-contracts/blob/master/LICENSE)

# Hyperdrive

Hyperdrive is an automated market maker that enables fixed-rate markets to be
built on top of arbitrary yield sources.

# Developing

## Pre-requisites

This repository makes use of [foundry](https://github.com/foundry-rs/foundry) to
build and test the smart contracts and uses several node.js packages to lint and
prettify the source code. Proceed through the following steps to set up the repository:
- [Install forge](https://github.com/foundry-rs/foundry#installatio://github.com/foundry-rs/foundry#installation)
- [Install yarn](https://yarnpkg.com/getting-started/install)
- Install lib/forge-std dependencies by running `forge install` from the project root
- Install node.js dependencies by running `yarn` from the project root

## Environment Variables

The test suite and migration scripts make use of several environment variables.
Copy `.env_template` to `.env` and populate the file with your private key and
provider URLs.

## Build

To build the smart contracts, run `yarn build`.

## Test

To test the smart contracts, run `yarn test`.

## Lint

We have several linters. Solhint is a Solidity linter that checks for best
practices and style, prettier is a Solidity formatter that checks for formatting
and style, and cSpell is a spell checker. To run all three, run `yarn lint`.
If you want to automatically format the code, run `yarn prettier`.

## Yield Sources

The current suggested way of integrating your yield source with hyperdrive is through the [ERC-4626 standard](https://eips.ethereum.org/EIPS/eip-4626) although accomodations can be made if this is not possible.

# Disclaimer

The language used in this codebase is for coding convenience only, and is not
intended to, and does not, have any particular legal or regulatory significance.
