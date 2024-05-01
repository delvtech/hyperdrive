# Hyperdrive Deploy w/ Hardhat

[Hardhat tasks](https://hardhat.org/hardhat-runner/docs/guides/tasks) are used to deploy the Hyperdrive contracts for the networks specified in [hardhat.config.ts](../hardhat.config.ts).

| :warning: Warning                                                                                                         |
|:--------------------------------------------------------------------------------------------------------------------------|
| Redeploying the same contracts for a network will overwrite the values in the [deployments folder](../deployments/).      |

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
  deploy:all                 	deploys the HyperdriveFactory and all deployer coordinators
  deploy:coordinators:all    	deploys all deployment coordinators
  deploy:coordinators:erc4626	deploys the ERC4626 deployment coordinator
  deploy:coordinators:reth   	deploys the RETH deployment coordinator
  deploy:coordinators:steth  	deploys the STETH deployment coordinator
  deploy:coordinators:ezeth   deploys the EzETH deployment coordinator
  deploy:factory             	deploys the hyperdrive factory to the configured chain
  deploy:forwarder           	deploys the ERC20ForwarderFactory to the configured chain
  deploy:instances:all       	deploys the ERC4626 deployment coordinator
  deploy:instances:erc4626   	deploys the ERC4626 deployment coordinator
  deploy:registry            	deploys the hyperdrive registry to the configured chain
```

## Configuration

Per-network configuration is defined in [hardhat.config.ts](../hardhat.config.ts). The values are then parsed by Zod to ensure adherance to the schema and transformed to more blockchain-friendly types. This layer of indirection enables the use of syntax sugar like using `"7 days"` in place of `604800`.

Many tasks also accept cli parameters at runtime to change their behavior.


### Schemas

**[Factory Schema](./deploy/factory.ts)**


**[Coordinator Schema](./deploy/coordinators/index.ts)**


**[Instance Schemas](./deploy/instances/)**


### Example Configuration

```ts
networks: {
  sepolia: {
    accounts: [env.PRIVATE_KEY!],
    url: env.SEPOLIA_RPC_URL!,
    verify: {
      etherscan: {
        apiKey: env.ETHERSCAN_API_KEY!,
      },
    },
    factory: {
      governance: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
      hyperdriveGovernance: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
      defaultPausers: ["0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8"],
      feeCollector: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
      sweepCollector: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
      checkpointDurationResolution: "8 hours",
      minCheckpointDuration: "24 hours",
      maxCheckpointDuration: "24 hours",
      minPositionDuration: "7 days",
      maxPositionDuration: "30 days",
      minFixedAPR: "0.01",
      maxFixedAPR: "0.6",
      minTimeStretchAPR: "0.01",
      maxTimeStretchAPR: "0.6",
      minFees: {
        curve: "0.001",
        flat: "0.0001",
        governanceLP: "0.15",
        governanceZombie: "0.03",
      },
      maxFees: {
        curve: "0.01",
        flat: "0.001",
        governanceLP: "0.15",
        governanceZombie: "0.03",
      },
    },
    // coordinators: {
    //   reth: "0x....",
    //   lido: "0x...."
    // },
    instances: {
      erc4626: [
        {
          name: "TESTERC4626",
          deploymentId: "0xabbabac",
          salt: "0x69420",
          contribution: "0.1",
          fixedAPR: "0.5",
          timestretchAPR: "0.5",
          options: {
            // destination: "0xsomeone",
            asBase: true,
            // extraData: "0x",
          },
          poolDeployConfig: {
            // baseToken: "0x...",
            // vaultSharesToken: "0x...",
            minimumShareReserves: "0.001",
            minimumTransactionAmount: "0.001",
            positionDuration: "30 days",
            checkpointDuration: "1 day",
            timeStretch: "0",
            governance: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
            feeCollector: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
            sweepCollector: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
            fees: {
              curve: "0.0100",
              flat: "0.0005",
              governanceLP: "0.015",
              governanceZombie: "0.003",
            },
          },
        },
      ],
    },
  },
}
```


