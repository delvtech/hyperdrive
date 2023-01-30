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
- Install node.js dependencies by running `yarn` from the project root

## Build

To build the smart contracts, run `yarn build`.

## Test

To test the smart contracts, run `yarn test`.

## Lint

We have several linters. Solhint is a Solidity linter that checks for best
practices and style, prettier is a Solidity formatter that checks for formatting
and style, and cSpell is a spell checker. To run all three, run `yarn lint`.
If you want to automatically format the code, run `yarn prettier`.
