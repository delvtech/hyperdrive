import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { subtask, types } from "hardhat/config";
import { Deployments } from "../deployments";
import { DeploySaveParams } from "../save";
import "../type-extensions";
import { validHyperdrivePrefixes } from "../types";
import { PoolDeployConfig } from "./schema";

dayjs.extend(duration);

export type DeployInstancesTargetsParams = {
  prefix: keyof typeof validHyperdrivePrefixes;
  name: string;
};

subtask(
  "deploy:instances:shared",
  "deploys the hyperdrive instance and its targets",
)
  .addParam(
    "prefix",
    "prefix of the hyperdrive instance (erc4626 | steth | reth)",
    undefined,
    types.string,
  )
  .addParam("name", "name of the hyperdrive instance", undefined, types.string)
  .setAction(
    async (
      { prefix, name }: DeployInstancesTargetsParams,
      { run, network, viem, getNamedAccounts, artifacts },
    ) => {
      let prefixValue = validHyperdrivePrefixes[prefix];
      let deployer = (await getNamedAccounts())["deployer"] as `0x${string}`;

      // Extract the correct config for the instance type.
      let config = network.config.instances
        ? network.config.instances[prefix]?.find((i) => i.name === name)
        : undefined;
      if (!config)
        throw new Error(
          `unable to find config for prefix '${prefix}' with name '${name}'`,
        );

      // Obtain data for the factory and connect a contract instance.
      let factoryDeployment = Deployments.get().byName(
        `HyperdriveFactory`,
        network.name,
      );
      let factory = await viem.getContractAt(
        "HyperdriveFactory",
        factoryDeployment.address as `0x${string}`,
      );

      // Obtain data for the coordinator and connect a contract instance.
      let coordinatorDeployment = Deployments.get().byName(
        `${prefixValue}HyperdriveDeployerCoordinator`,
        network.name,
      );
      let coordinator = await viem.getContractAt(
        `HyperdriveDeployerCoordinator`,
        coordinatorDeployment.address as `0x${string}`,
      );

      // Add the linkerFactory and codeHash to the poolDeployConfig.
      let poolDeployConfig = {
        ...config.poolDeployConfig,
        linkerFactory: await factory.read.linkerFactory(),
        linkerCodeHash: await factory.read.linkerCodeHash(),
      } as PoolDeployConfig;

      // Deploy the targets (saving and verification will be performed later)
      let pc = await viem.getPublicClient();
      let initialVaultSharePrice;
      let targets: `0x${string}`[] = [];
      for (let i = 0; i < 5; i++) {
        console.log(`deploying ${name}_${prefixValue}Target${i}`);
        let args = [
          config.deploymentId,
          coordinator.address,
          poolDeployConfig,
          config.options.extraData,
          config.fixedAPR,
          config.timestretchAPR,
          BigInt(i),
          config.salt,
        ];
        // Simulating the deployment as a separate step is necessary
        // to obtain the return value from a viem contract write.
        let { result: address } = await factory.simulate.deployTarget(
          args as any,
          {
            gas: 10_000_000n,
          },
        );
        targets.push(address);
        await pc.waitForTransactionReceipt({
          hash: await factory.write.deployTarget(args as any, {
            gas: 10_000_000n,
          }),
          confirmations: network.live ? 3 : 1,
        });
        // Load the abi from the compilation artifacts for verification.
        let { abi } = artifacts.readArtifactSync(`${prefixValue}Target${i}`);
        // The initial vault share price is part of the constructor arguments
        // for the contract which are needed for verification. It remains
        // the same across all targets, only retrieve it once to avoid
        // unnecessary network requests.
        if (i == 0) {
          initialVaultSharePrice = (
            await coordinator.read.deployments([config.deploymentId])
          ).initialSharePrice;
        }
        // Save the artifacts and verify
        await run("deploy:save", {
          name: `${name}_${prefixValue}Target${i}`,
          args: [{ ...poolDeployConfig, initialVaultSharePrice }],
          abi,
          address,
          contract: `${prefixValue}Target${i}`,
        } as DeploySaveParams);
      }

      // Deploy hyperdrive
      console.log(`deploying ${name}_${prefixValue}Hyperdrive`);
      let args = [
        config.deploymentId,
        coordinator.address,
        poolDeployConfig,
        config.options.extraData,
        config.contribution,
        config.fixedAPR,
        config.timestretchAPR,
        {
          ...config.options,
          destination: config.options.destination ?? deployer,
        },
        config.salt,
      ];
      // Simulating the deployment as a separate step is necessary
      // to obtain the return value from a viem contract write.
      let { result: hyperdriveAddress } =
        await factory.simulate.deployAndInitialize(args as any, {
          gas: 10_000_000n,
        });
      let hyperdriveTX = await factory.write.deployAndInitialize(args as any, {
        gas: 10_000_000n,
      });
      await pc.waitForTransactionReceipt({ hash: hyperdriveTX });

      // Load the abi from the compilation artifacts for verification.
      let { abi } = artifacts.readArtifactSync(`${prefixValue}Hyperdrive`);
      await run("deploy:save", {
        name: `${name}_${prefixValue}Hyperdrive`,
        args: [
          {
            ...poolDeployConfig,
            initialVaultSharePrice,
          },
          ...targets,
        ],
        abi,
        address: hyperdriveAddress,
        contract: `${prefixValue}Hyperdrive`,
      } as DeploySaveParams);
    },
  );
