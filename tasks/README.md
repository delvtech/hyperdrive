# Hyperdrive Deploy w/ Hardhat

[Hardhat tasks](https://hardhat.org/hardhat-runner/docs/guides/tasks) are used to deploy the Hyperdrive contracts for the networks specified in [hardhat.config.ts](../hardhat.config.ts).

Deploys are resumable, and flags must be used to override the default behavior of preserving
existing deployments.

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
  deploy                Deploy contracts
  deploy:all            deploys the HyperdriveFactory, all deployer coordinators, and all hyperdrive instances
  deploy:coordinator    deploys the HyperdriveDeployerCoordinator with the provided name and chain
  deploy:factory        deploys the HyperdriveFactory with the provided name and chain
  deploy:instance       deploys the Hyperdrive instance with the provided name and chain
  deploy:registry       deploys the hyperdrive factory to the configured chain
  etherscan-verify      submit contract source code to etherscan
```

For example, to deploy the 30 DAI pool on sepolia, you can run the following command:

```sh
npx hardhat deploy:instance --name DAI_30_DAY --network sepolia
```

## Configuration

Per-network configuration must be imported to [hardhat.config.ts](../hardhat.config.ts). The values are then parsed by Zod to ensure adherance to the schema and transformed to more blockchain-friendly types. This layer of indirection enables the use of syntax sugar like using `"7 days"` in place of `604800`.

Many tasks also accept cli parameters at runtime to change their behavior.

[Schemas](./deploy/lib/schemas.ts)

### Example Configuration

[Hyperdrive Instance](./deploy/config/sepolia/dai-14day.ts)

[Hyperdrive DeployerCoordinator](./deploy/config/sepolia/erc4626-coordinator.ts)

[Hyperdrive Factory](./deploy/config/sepolia/factory.ts)

