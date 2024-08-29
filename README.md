[![Tests](https://github.com/delvtech/hyperdrive/actions/workflows/solidity_test.yml/badge.svg)](https://github.com/delvtech/hyperdrive/actions/workflows/solidity_test.yml)
[![Coverage](https://coveralls.io/repos/github/delvtech/hyperdrive/badge.svg?branch=main&t=vnW3xG&kill_cache=1&service=github)](https://coveralls.io/github/delvtech/hyperdrive?branch=main)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://github.com/delvtech/elf-contracts/blob/master/LICENSE)
[![Static Badge](https://img.shields.io/badge/DELV-Terms%20Of%20Service-orange)](https://delv-public.s3.us-east-2.amazonaws.com/delv-terms-of-service.pdf)

<img src="icons/hyperdrive_winter.webp" width="800" alt="hyperdrive"><br>

# Hyperdrive

Hyperdrive is an automated market maker that enables fixed-rate markets to be
built on top of arbitrary yield sources. Hyperdrive provides several novel
features for fixed-rate AMMs including:

- Terms on Demand: Hyperdrive allows for minting to be a part of the
AMM, where the AMM essentially underwrites a new term for the user
whenever they open a position. The user is not constrained to purchasing,
selling, or minting into preexisting terms that are partially matured.
- Continuous Liquidity: Hyperdrive pools never expire and underwrite a
variety of fixed and variable rate terms with differing maturity dates. LPs
can provide liquidity once without needing to roll their liquidity over to
new terms.
- Single-Sided Liquidity: Hyperdrive liquidity providers are only required to
provide base assets. The fact that LPs don't need to mint bonds to provide
liquidity improves the capital efficiency and UX of providing liquidity to
fixed-rate markets.

# Deployed Contracts

The addresses for all of the DELV approved deployed Hyperdrive contracts can be found [here](https://app.hyperdrive.box/chainlog).

# Resources

The [Hyperdrive docs](https://docs-delv.gitbook.io/hyperdrive) include documentation
on how to use Hyperdrive to source and provide liquidity, documentation for
developers seeking to use Hyperdrive programatically, and documentation for
developers that want to integrate Hyperdrive with a yield source.

The [Hyperdrive Whitepaper](./docs/Hyperdrive_Whitepaper.pdf) describes the technical
details underlying how Hyperdrive mints terms on demand, enables LPs to provide
everlasting liquidity, and explains how the AMM's pricing model works.

The [`audits/`](./audits) directory contains the reports for all of the audits that
have been conducted for Hyperdrive to date.

# Repository Layout

The Hyperdrive interface can be found in [`IHyperdrive.sol`](./contracts/src/interfaces/IHyperdrive.sol).
This interface includes all of the read and write functions available on each Hyperdrive
instance as well as the events emitted by Hyperdrive and the custom errors used by Hyperdrive.

The existing Hyperdrive instances can be found in [`contracts/src/instances/`](./contracts/src/instances/).
These instances can serve as a reference for integrators that would like to integrate
a yield source with Hyperdrive. The `ERC4626Hyperdrive` instance found in
[`contracts/src/instances/erc4626/`](./contracts/src/instances/erc4626/) can be
used to integrate `ERC4626` compliant yield sources. For yield sources that require
direct integrations, the other instances can serve as a reference for how integrations
are structured.

Because of the code size limits imposed by [EIP-170](https://eips.ethereum.org/EIPS/eip-170),
Hyperdrive's logic is sharded over several different contracts. The code that
supports the proxy architecture can be found in [`contracts/src/external`](./contracts/src/external/).
These contracts are abstract since several functions must be implemented on a case-by-case basis
for different yield sources.

The core logic used in the Hyperdrive AMM can be found in [`contracts/src/internal/`](./contracts/src/internal/).
This logic relies on libraries that can be found in [`contracts/src/libraries/`](./contracts/src/libraries/).

The `HyperdriveFactory` contract can be found in [`HyperdriveFactory.sol`](./contracts/src/factory/HyperdriveFactory.sol).
This contract makes it easy to deploy and initialize new pools. The factory utilizes
deployer coordinators that correspond to Hyperdrive instances. These deployer
coordinators and the deployer contracts used by the coordinators can be found in
[`contracts/src/deployers/`](./contracts/src/deployers/).

# Getting Started

## Pre-requisites

This repository makes use of [foundry](https://github.com/foundry-rs/foundry) to
build and test the smart contracts and uses several node.js packages to lint and
prettify the source code. Proceed through the following steps to set up the repository:
- [Install forge](https://github.com/foundry-rs/foundry#installatio://github.com/foundry-rs/foundry#installation)
- [Install yarn](https://yarnpkg.com/getting-started/install)
- Install lib/forge-std dependencies by running `forge install` from the project root
- Install node.js dependencies by running `yarn` from the project root
- Install [pypechain](https://github.com/delvtech/pypechain) by running `pip install pypechain` from the project root (we recommend using a virtual environment with python 3.10)

## Environment Variables

The test suite and migration scripts make use of several environment variables.
Copy `.env_template` to `.env` and populate the file with your private key and
provider URLs.

## Build

To build the smart contracts, run:

```sh
make build
```

## Test

To test the smart contracts, run:

```sh
make test
```


## Lint

We have several linters. Solhint is a Solidity linter that checks for best
practices and style, prettier is a Solidity formatter that checks for formatting
and style, and cSpell is a spell checker. To run all three, run:

```sh
make lint
```

If you want to automatically format the code, run:

```sh
make prettier
```

## Deploy

To deploy the smart contracts, run:

```sh
NETWORK=<hardhat|anvil|sepolia|mainnet> make deploy
```

To deploy the smart contracts to a mainnet fork environment:

1. Add the contract deploy configuration(s) to `tasks/deploy/config/mainnet/`.
Make sure to import the configuration objects in
`tasks/deploy/config/mainnet/index.ts`.

1. Update `hardhat.config.mainnet_fork.ts` to include the new deployment
configurations.

1. In one terminal, start a local anvil fork instance:

    ```sh
    anvil --fork-url <your_mainnet_rpc_url>
    ```

1. In another terminal, bootstrap the `mainnet_fork` network's deployments in
`deployments.local.json` with the mainnet contract addresses.

    ```sh
    ./scripts/bootstrap-fork.sh
    ```

1. Deploy any new contracts present in `hardhat.config.mainnet_fork.ts` that
have not already been deployed on mainnet.

    ```sh
    NETWORK=mainnet_fork ADMIN=<your_deployer_address> ./scripts/deploy-fork.sh
    ```

To update the remote fork with these changes, first create a pull request and
obtain the latest version for the `devnet` image. The changes will be reflected
automatically after updating the remote fork's `devnet` image version and
restarting the containers.

### Generate Deploy Configurations

Factory, coordinator, and instance deploy configurations can be generated via templates.

To get started, create a new variable file from the sample by running:

```sh
cp \
  tasks/deploy/config/<factory|coordinator|instance>.sample.env \
  <factory|coordinator|instance>.env
```

Next, set values for each of the fields in the file `<factory|coordinator|instance>.env`. Sample values are provided as examples, but should be overwritten.

Finally, to generate the configuration files run:

```sh
make generate-deploy
```

The above command will output next steps to integrate the new configuration files with existing configuration.

# Disclaimer

The language used in this code and documentation is not intended to, and does not, have any particular financial, legal, or regulatory significance.

---

Copyright © 2024  DELV

Licensed under the Apache License, Version 2.0 (the "OSS License").

By accessing or using this code, you signify that you have read, understand and agree to be bound by and to comply with the [OSS License](http://www.apache.org/licenses/LICENSE-2.0) and [DELV's Terms of Service](https://delv-public.s3.us-east-2.amazonaws.com/delv-terms-of-service.pdf). If you do not agree to those terms, you are prohibited from accessing or using this code.

Unless required by applicable law or agreed to in writing, software distributed under the OSS License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the OSS License and the DELV Terms of Service for the specific language governing permissions and limitations.
