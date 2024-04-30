import { subtask, types } from "hardhat/config";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { PoolDeployConfig } from "./schema";
import "../type-extensions";
import { validHyperdrivePrefixes } from "../utils";

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
      { deployments, run, network, viem, getNamedAccounts },
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

      // Obtain data for the factory and connect to it.
      let factoryDeployment = await deployments.get(`HyperdriveFactory`);
      let factory = await viem.getContractAt(
        "HyperdriveFactory",
        factoryDeployment.address as `0x${string}`,
      );

      // Obtain data for the coordinator and connect to it.
      let coordinatorDeployment = await deployments.get(
        `${prefixValue}HyperdriveDeployerCoordinator`,
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
      for (let i = 0; i < 5; i++) {
        console.log(`deploying ${name}_${prefixValue}Target${i}`);
        let tx = await factory.write.deployTarget(
          [
            config.deploymentId,
            coordinator.address,
            poolDeployConfig,
            config.options.extraData,
            config.fixedAPR,
            config.timestretchAPR,
            BigInt(i),
            config.salt,
          ],
          { gas: 10_000_000n },
        );
        await pc.waitForTransactionReceipt({ hash: tx });
      }

      // Deploy hyperdrive (saving and verification will be performed later)
      console.log(`deploying ${name}_${prefixValue}Hyperdrive`);
      let tx = await factory.write.deployAndInitialize(
        [
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
        ],
        { gas: 10_000_000n },
      );
      await pc.waitForTransactionReceipt({ hash: tx });

      // Obtain data for verification from the coordinator
      let {
        target0,
        target1,
        target2,
        target3,
        target4,
        initialSharePrice,
        hyperdrive,
      } = await coordinator.read.deployments([config.deploymentId]);
      let targets = [target0, target1, target2, target3, target4];
      let poolConfig = {
        ...poolDeployConfig,
        initialVaultSharePrice: initialSharePrice,
      };

      // Verify and save the target deployments.
      for (let i = 0; i < 5; i++) {
        await deployments.save(`${name}_${prefixValue}Target${i}`, {
          address: targets[i],
          ...(await deployments.getArtifact(`${prefixValue}Target${i}`)),
          args: [poolConfig],
        });
        await run("deploy:verify", {
          name: `${name}_${prefixValue}Target${i}`,
        });
      }

      // Verify and save the hyperdrive deployment.
      await deployments.save(`${name}_${prefixValue}Hyperdrive`, {
        address: hyperdrive,
        ...(await deployments.getArtifact(`${prefixValue}Hyperdrive`)),
        args: [poolConfig, ...targets],
      });
      await run("deploy:verify", { name: `${name}_${prefixValue}Hyperdrive` });
    },
  );
