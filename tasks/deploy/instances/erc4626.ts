import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { task, types } from "hardhat/config";
import { parseEther, toFunctionSelector } from "viem";
import { z } from "zod";
import { Deployments } from "../deployments";
import { DeploySaveParams } from "../save";
import { DeployInstanceParams, zInstanceDeployConfig } from "./schema";

dayjs.extend(duration);

export let zERC4626InstanceDeployConfig = zInstanceDeployConfig.superRefine(
  (v, c) => {
    // Ensure either both tokens are specified or no tokens are specified in the configuration
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
    // Modify the base Hyperdrive configuration to enforce `asBase=true` when tokens are unspecified
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
  },
);

export type ERC4626InstanceDeployConfigInput = z.input<
  typeof zERC4626InstanceDeployConfig
>;
export type ERC4626InstanceDeployConfig = z.infer<
  typeof zERC4626InstanceDeployConfig
>;

task("deploy:instances:erc4626", "deploys the ERC4626 deployment coordinator")
  .addParam("name", "name of the instance to deploy", undefined, types.string)
  .addOptionalParam("admin", "admin address", undefined, types.string)
  .addOptionalParam(
    "overwrite",
    "overwrite deployment artifacts if they exist",
    false,
    types.boolean,
  )
  .setAction(
    async (
      { name, admin, overwrite }: DeployInstanceParams,
      { run, network, viem, getNamedAccounts, config: hardhatConfig },
    ) => {
      if (
        !overwrite &&
        Deployments.get().byNameSafe(`${name}_ERC4626Target0`, network.name)
      ) {
        console.log(`${name}_ERC4626Hyperdrive already deployed`);
        return;
      }
      console.log(`starting hyperdrive deployment ${name}`);
      let deployer = (await getNamedAccounts())["deployer"] as `0x${string}`;
      // Read and parse the provided configuration file
      let config = hardhatConfig.networks[
        network.name
      ].instances?.erc4626?.find((i) => i.name === name);
      if (!config)
        throw new Error(
          `unable to find instance for network ${network.name} with name ${name}`,
        );

      // Set 'admin' to the deployer address if not specified via param
      if (!admin?.length) admin = deployer;

      // Get the address and contract for the deployer coordinator
      let coordinatorAddress = Deployments.get().byName(
        "ERC4626HyperdriveDeployerCoordinator",
        network.name,
      )?.address as `0x${string}`;

      // Deploy mock assets if baseToken and vaultSharesToken are left unspecified
      if (
        !config.poolDeployConfig.baseToken?.length &&
        !config.poolDeployConfig.vaultSharesToken?.length
      ) {
        // deploy base token
        let baseTokenName = name + "_BASE";
        console.log("deploying mock baseToken...");
        // NOTE: constructor args have to be specified inline due to viem's type inferencing.
        let baseToken = await viem.deployContract("ERC20Mintable", [
          baseTokenName,
          baseTokenName,
          18,
          admin as `0x${string}`,
          true,
          parseEther("10000"),
        ]);
        await run("deploy:save", {
          name: baseTokenName,
          args: [
            baseTokenName,
            baseTokenName,
            18,
            admin as `0x${string}`,
            true,
            parseEther("10000"),
          ],
          abi: baseToken.abi,
          address: baseToken.address,
          contract: "ERC20Mintable",
        } as DeploySaveParams);
        config.poolDeployConfig.baseToken = baseToken.address;
        await baseToken.write.approve([
          coordinatorAddress,
          config.contribution,
        ]);
        // deploy shares token
        let vaultSharesTokenName = name + "_SHARES";
        console.log("deploying mock vaultSharesToken...");
        // NOTE: constructor args have to be specified inline due to viem's type inferencing.
        let vaultSharesToken = await viem.deployContract("MockERC4626", [
          baseToken.address,
          vaultSharesTokenName,
          vaultSharesTokenName,
          parseEther("0.13"),
          admin as `0x${string}`,
          true,
          parseEther("10000"),
        ]);
        await run("deploy:save", {
          name: vaultSharesTokenName,
          args: [
            baseToken.address,
            vaultSharesTokenName,
            vaultSharesTokenName,
            parseEther("0.13"),
            admin as `0x${string}`,
            true,
            parseEther("10000"),
          ],
          abi: vaultSharesToken.abi,
          address: vaultSharesToken.address,
          contract: "MockERC4626",
        } as DeploySaveParams);
        config.poolDeployConfig.vaultSharesToken = vaultSharesToken.address;
        await vaultSharesToken.write.approve([
          coordinatorAddress,
          config.contribution,
        ]);

        // Open up minting
        await baseToken.write.setPublicCapability([
          toFunctionSelector("mint(uint256)"),
          true,
        ]);
        await baseToken.write.setPublicCapability([
          toFunctionSelector("mint(address,uint256)"),
          true,
        ]);

        // Mint the deployer some base tokens for the contribution.
        console.log("minting base tokens for contribution...");
        await baseToken.write.mint([config.contribution]);
      }

      // Deploy the targets and hyperdrive instance.
      await run("deploy:instances:shared", { prefix: "erc4626", name });
    },
  );
