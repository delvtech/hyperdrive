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
      { deployments, run, network, viem, getNamedAccounts, artifacts },
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
      let factoryDeployment = await deployments.get(`HyperdriveFactory`);
      let factory = await viem.getContractAt(
        "HyperdriveFactory",
        factoryDeployment.address as `0x${string}`,
      );

      // Obtain data for the coordinator and connect a contract instance.
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
      let initialVaultSharePrice = 0n;
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
        });
        let { abi, bytecode } = artifacts.readArtifactSync(
          `${prefixValue}Target${i}`,
        );
        if (i == 0)
          initialVaultSharePrice = (
            await coordinator.read.deployments([config.deploymentId])
          ).initialSharePrice;
        await deployments.save(`${name}_${prefixValue}Target${i}`, {
          abi,
          bytecode,
          address,
          args: [{ ...poolDeployConfig, initialVaultSharePrice }],
        });
        await run("deploy:verify", {
          name: `${name}_${prefixValue}Target${i}`,
        });
      }

      // Deploy hyperdrive (saving and verification will be performed later)
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
      let { result: hyperdriveAddress, request } =
        await factory.simulate.deployAndInitialize(args as any, {
          gas: 10_000_000n,
        });
      let hyperdriveTX = await factory.write.deployAndInitialize(args as any, {
        gas: 10_000_000n,
      });
      await pc.waitForTransactionReceipt({ hash: hyperdriveTX });

      // Verify and save the hyperdrive deployment.
      let { abi, bytecode } = artifacts.readArtifactSync(
        `${prefixValue}Hyperdrive`,
      );
      await deployments.save(`${name}_${prefixValue}Hyperdrive`, {
        abi,
        bytecode,
        address: hyperdriveAddress,
        args: [
          {
            ...poolDeployConfig,
            initialVaultSharePrice,
          },
          ...targets,
        ],
      });
      await run("deploy:verify", { name: `${name}_${prefixValue}Hyperdrive` });
    },
  );
