# Hyperdrive Deploy w/ Hardhat

[Hardhat tasks](https://hardhat.org/hardhat-runner/docs/guides/tasks) are used to deploy the Hyperdrive contracts for the networks specified in [hardhat.config.ts](../hardhat.config.ts).

Deploys are resumable and ensured to not duplicate items on a network unless they are deleted from
the [deployments.json](../deployments.json).

## TLDR

```sh
npx hardhat deploy:all
```

## Tasks

The complete list of tasks can be seen by running `npx hardhat --help` in your terminal.

| :warning: Warning                                                                                                                     |
|:--------------------------------------------------------------------------------------------------------------------------------------|
| The bare `deploy` task is unrelated to our deployment process and SHOULD NOT BE RUN. It will be disabled/overridden in the future     |

```sh
  deploy:hyperdrive     deploys the HyperdriveFactory, all deployer coordinators, and all hyperdrive instances
  deploy:verify         attempts to verify all deployed contracts for the specified network
```

The `deploy:hyperdrive` task should be run for all deployments. It handles resuming existing deploys
and only deploys configurations that are not already present on the specified chain. It must be
provided a `--network` flag.

### Examples

Deploy all sepolia contracts

```sh
npx hardhat deploy:hyperdrive --network sepolia --show-stack-traces
```

Verify all sepolia contracts

```sh
npx hardhat deploy:verify --network sepolia --show-stack-traces
```

## Configuration

Per-network configuration must be imported to [hardhat.config.ts](../hardhat.config.ts). The types
used for the configuration objects are derived directly from the contract abi's. Breaking changes to
the underlying contracts will cause compile-time errors for the configurations and deploys will not
be able to be run until these are fixed.

[Schemas](./deploy/lib/schemas.ts)

### Example Configuration

[Hyperdrive Instance](./deploy/config/sepolia/dai-14day.ts)

[Hyperdrive DeployerCoordinator](./deploy/config/sepolia/erc4626-coordinator.ts)

[Hyperdrive Factory](./deploy/config/sepolia/factory.ts)

