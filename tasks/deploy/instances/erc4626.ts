import { task, types } from "hardhat/config";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import {
  Prettify,
  zAddress,
  zBytes32,
  zDuration,
  zEther,
  zHex,
} from "../utils";
import { z } from "zod";
import { parseEther } from "viem";
import util from "util";

dayjs.extend(duration);

// Schema for hyperdrive instance configuration to be read in from a JSON file
export const zERC4626InstanceDeployConfig = z
  .object({
    name: z.string(),
    deploymentId: zBytes32,
    salt: zBytes32,
    contribution: zEther,
    fixedAPR: zEther,
    timestretchAPR: zEther,
    options: z.object({
      destination: zAddress.optional(),
      asBase: z.boolean().default(true),
      extraData: zHex.default("0x"),
    }),
    poolDeployConfig: z
      .object({
        baseToken: zAddress.optional(),
        vaultSharesToken: zAddress.optional(),
        minimumShareReserves: zEther,
        minimumTransactionAmount: zEther,
        positionDuration: zDuration,
        checkpointDuration: zDuration,
        timeStretch: zEther,
        governance: zAddress,
        feeCollector: zAddress,
        sweepCollector: zAddress,
        fees: z.object({
          curve: zEther,
          flat: zEther,
          governanceLP: zEther,
          governanceZombie: zEther,
        }),
      })
      .transform((v) => ({
        ...v,
        fees: {
          ...v.fees,
          flat:
            v.fees.flat /
            (BigInt(dayjs.duration(365, "days").asSeconds()) /
              v.positionDuration),
        },
      })),
  })
  .superRefine((v, c) => {
    if (
      !!v.poolDeployConfig.baseToken?.length &&
      !v.poolDeployConfig.vaultSharesToken?.length
    ) {
      c.addIssue({
        code: z.ZodIssueCode.custom,
        message:
          "Both tokens must be specified or both tokens must be unspecified... `baseToken` was specified but `vaultSharesToken` was not.",
        path: ["vaultSharesToken"],
      });
    }
    if (
      !v.poolDeployConfig.baseToken?.length &&
      !!v.poolDeployConfig.vaultSharesToken?.length
    ) {
      c.addIssue({
        code: z.ZodIssueCode.custom,
        message:
          "Both tokens must be specified or both tokens must be unspecified... `vaultSharesToken` was specified but `baseToken` was not.",
        path: ["baseToken"],
      });
    }
    if (
      !v.poolDeployConfig.baseToken &&
      !v.poolDeployConfig.vaultSharesToken &&
      !v.options.asBase
    ) {
      c.addIssue({
        code: z.ZodIssueCode.custom,
        message:
          "Please set `options.asBase` to true when `baseToken` and `vaultSharesToken` are unspecified",
        path: ["options.asBase"],
      });
    }
  });

export type ERC4626InstanceDeployConfigInput = z.input<
  typeof zERC4626InstanceDeployConfig
>;
export type ERC4626InstanceDeployConfig = z.infer<
  typeof zERC4626InstanceDeployConfig
>;

// Solidity representation of the config that is passed as a constructor argument when creating instances
export type PoolDeployConfig = Prettify<
  ERC4626InstanceDeployConfig["poolDeployConfig"] & {
    linkerFactory: `0x${string}`;
    linkerCodeHash: `0x${string}`;
  }
>;

export type PoolConfig = Prettify<
  PoolDeployConfig & {
    initialVaultSharePrice: bigint;
  }
>;

export type DeployInstanceParams = {
  name: string;
  admin?: string;
};

task("deploy:instances:erc4626", "deploys the ERC4626 deployment coordinator")
  .addParam("name", "name of the instance to deploy", undefined, types.string)
  .addOptionalParam("admin", "admin address", undefined, types.string)
  .setAction(
    async (
      { name, admin }: DeployInstanceParams,
      {
        deployments,
        run,
        network,
        viem,
        getNamedAccounts,
        config: hardhatConfig,
      },
    ) => {
      const deployer = (await getNamedAccounts())["deployer"] as `0x${string}`;
      // Read and parse the provided configuration file
      const config = hardhatConfig.networks[
        network.name
      ].instances?.erc4626?.find((i) => i.name === name);
      if (!config)
        throw new Error(
          `unable to find instance for network ${network.name} with name ${name}`,
        );
      console.log(util.inspect(config, false, null, true /* enable colors */));

      // Set 'admin' to the deployer address if not specified via param
      if (!admin?.length) admin = deployer;

      // Get the address for the deployer coordinator
      const coordinatorAddress = (
        await deployments.get("ERC4626HyperdriveDeployerCoordinator")
      ).address as `0x${string}`;
      const coordinator = await viem.getContractAt(
        "ERC4626HyperdriveDeployerCoordinator",
        coordinatorAddress,
      );

      // Deploy mock assets if baseToken and vaultSharesToken are left unspecified
      if (
        !config.poolDeployConfig.baseToken?.length &&
        !config.poolDeployConfig.vaultSharesToken?.length
      ) {
        // deploy base token
        const baseTokenName = name + "_BASE";
        console.log("deploying mock baseToken...");
        // NOTE: constructor args have to be specified inline due to viem's type inferencing.
        const baseToken = await viem.deployContract("ERC20Mintable", [
          baseTokenName,
          baseTokenName,
          18,
          admin as `0x${string}`,
          true,
          parseEther("10000"),
        ]);
        await deployments.save(baseTokenName, baseToken);
        if (network.name != "hardhat")
          await run("verify:verify", {
            address: baseToken.address,
            constructorArguments: [
              baseTokenName,
              baseTokenName,
              18,
              admin as `0x${string}`,
              true,
              parseEther("10000"),
            ],
            network: network.name,
          });
        config.poolDeployConfig.baseToken = baseToken.address;

        // deploy shares token
        const vaultSharesTokenName = name + "_SHARES";
        console.log("deploying mock vaultSharesToken...");
        // NOTE: constructor args have to be specified inline due to viem's type inferencing.
        const vaultSharesToken = await viem.deployContract("MockERC4626", [
          baseToken.address,
          vaultSharesTokenName,
          vaultSharesTokenName,
          parseEther("0.13"),
          admin as `0x${string}`,
          true,
          parseEther("10000"),
        ]);
        await deployments.save(vaultSharesTokenName, vaultSharesToken);
        if (network.name != "hardhat")
          await run("verify:verify", {
            address: vaultSharesToken.address,
            constructorArguments: [
              baseToken.address,
              vaultSharesTokenName,
              vaultSharesTokenName,
              parseEther("0.13"),
              admin as `0x${string}`,
              true,
              parseEther("10000"),
            ],
            network: network.name,
          });
        config.poolDeployConfig.vaultSharesToken = vaultSharesToken.address;

        // Mint the deployer some base tokens if they don't have a sufficient amount for the contribution.
        const baseBalance = await baseToken.read.balanceOf([deployer]);
        if (baseBalance < config.contribution) {
          console.log("minting base tokens for contribution...");
          await baseToken.write.mint([
            deployer,
            config.contribution - baseBalance,
          ]);
        }
      }

      // Ensure the deployer has approved the deployer coordinator for the appropriate token
      const token = await viem.getContractAt(
        "ERC20Mintable",
        config.options.asBase
          ? (config.poolDeployConfig.baseToken as `0x${string}`)
          : (config.poolDeployConfig.vaultSharesToken as `0x${string}`),
      );
      const allowance = await token.read.allowance([
        deployer,
        coordinatorAddress,
      ]);
      if (allowance < config.contribution) {
        console.log("approving coordinator for contribution...");
        await token.write.approve([coordinatorAddress, config.contribution]);
      }

      // Get the address and contract for the forwarder factory
      console.log("reading ERC20ForwarderFactory code hash...");
      const forwarderAddress = (await deployments.get("ERC20ForwarderFactory"))
        .address as `0x${string}`;
      const forwarder = await viem.getContractAt(
        "ERC20ForwarderFactory",
        forwarderAddress,
      );

      // Create the PoolDeployConfig
      const poolDeployConfig: PoolDeployConfig = {
        ...config.poolDeployConfig,
        linkerFactory: forwarderAddress as `0x${string}`,
        linkerCodeHash: await forwarder.read.ERC20LINK_HASH(),
      };

      // Load the factory contract
      const factoryAddress = (await deployments.get("HyperdriveFactory"))
        .address as `0x${string}`;
      const factory = await viem.getContractAt(
        "HyperdriveFactory",
        factoryAddress,
      );

      // Deploy target0
      console.log(`deploying ${name} ERC4626Target0...`);
      const target0 = await factory.write.deployTarget([
        config.deploymentId,
        coordinatorAddress,
        poolDeployConfig as Required<PoolDeployConfig>,
        config.options.extraData,
        config.fixedAPR,
        config.timestretchAPR,
        0n,
        config.salt,
      ]);
      await deployments.save(
        `${name}_ERC4626Target0`,
        await viem.getContractAt("ERC4626Target0", target0 as `0x${string}`),
      );
      if (network.name != "hardhat")
        await run("verify:verify", {
          contract: "ERC4626Target0",
          address: target0,
          constructorArguments: [poolDeployConfig],
          network: network.name,
        });

      // Deploy target1
      console.log(`deploying ${name} ERC4626Target1...`);
      const target1 = await factory.write.deployTarget([
        config.deploymentId,
        coordinatorAddress,
        poolDeployConfig as Required<PoolDeployConfig>,
        config.options.extraData,
        config.fixedAPR,
        config.timestretchAPR,
        1n,
        config.salt,
      ]);
      await deployments.save(
        `${name}_ERC4626Target1`,
        await viem.getContractAt("ERC4626Target1", target1 as `0x${string}`),
      );
      if (network.name != "hardhat")
        await run("verify:verify", {
          contract: "ERC4626Target1",
          address: target1,
          constructorArguments: [poolDeployConfig],
          network: network.name,
        });

      // Deploy target2
      console.log(`deploying ${name} ERC4626Target2...`);
      const target2 = await factory.write.deployTarget([
        config.deploymentId,
        coordinatorAddress,
        poolDeployConfig as Required<PoolDeployConfig>,
        config.options.extraData,
        config.fixedAPR,
        config.timestretchAPR,
        2n,
        config.salt,
      ]);
      await deployments.save(
        `${name}_ERC4626Target2`,
        await viem.getContractAt("ERC4626Target2", target2 as `0x${string}`),
      );
      if (network.name != "hardhat")
        await run("verify:verify", {
          contract: "ERC4626Target2",
          address: target2,
          constructorArguments: [poolDeployConfig],
          network: network.name,
        });

      // Deploy target3
      console.log(`deploying ${name} ERC4626Target3...`);
      const target3 = await factory.write.deployTarget([
        config.deploymentId,
        coordinatorAddress,
        poolDeployConfig as Required<PoolDeployConfig>,
        config.options.extraData,
        config.fixedAPR,
        config.timestretchAPR,
        3n,
        config.salt,
      ]);
      await deployments.save(
        `${name}_ERC4626Target3`,
        await viem.getContractAt("ERC4626Target3", target3 as `0x${string}`),
      );
      if (network.name != "hardhat")
        await run("verify:verify", {
          contract: "ERC4626Target3",
          address: target3,
          constructorArguments: [poolDeployConfig],
          network: network.name,
        });

      // Deploy target4
      console.log(`deploying ${name} ERC4626Target4...`);
      const target4 = await factory.write.deployTarget([
        config.deploymentId,
        coordinatorAddress,
        poolDeployConfig as Required<PoolDeployConfig>,
        config.options.extraData,
        config.fixedAPR,
        config.timestretchAPR,
        4n,
        config.salt,
      ]);
      await deployments.save(
        `${name}_ERC4626Target4`,
        await viem.getContractAt("ERC4626Target4", target4 as `0x${string}`),
      );
      if (network.name != "hardhat")
        await run("verify:verify", {
          contract: "ERC4626Target4",
          address: target4,
          constructorArguments: [poolDeployConfig],
          network: network.name,
        });

      // Deploy hyperdrive
      console.log(`deploying ${name} Hyperdrive`);
      const hyperdrive = await factory.write.deployAndInitialize([
        config.deploymentId,
        coordinatorAddress,
        poolDeployConfig as Required<PoolDeployConfig>,
        config.options.extraData,
        config.contribution,
        config.fixedAPR,
        config.timestretchAPR,
        {
          ...config.options,
          destination: config.options.destination ?? deployer,
        },
        config.salt,
      ]);
      const hyperdriveContract = await viem.getContractAt(
        "IHyperdriveRead",
        hyperdrive as `0x${string}`,
      );
      await deployments.save(
        `${name}_ERC4626Hyperdrive`,
        await viem.getContractAt(
          "ERC4626Hyperdrive",
          hyperdrive as `0x${string}`,
        ),
      );
      if (network.name != "hardhat")
        await run("verify:verify", {
          contract: "ERC4626Hyperdrive",
          address: hyperdrive,
          constructorArguments: [
            await hyperdriveContract.read.getPoolConfig(),
            target0,
            target1,
            target2,
            target3,
            target4,
          ],
          network: network.name,
        });
    },
  );
