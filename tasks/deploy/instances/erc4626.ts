import { task, types } from "hardhat/config";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { z } from "zod";
import { parseEther, toFunctionSelector } from "viem";
import util from "util";
import {
  DeployInstanceParams,
  PoolConfig,
  PoolDeployConfig,
  zInstanceDeployConfig,
} from "./schema";
import { buildModule } from "@nomicfoundation/ignition-core";
import { zEther, zDuration } from "../utils";

dayjs.extend(duration);

// const alt = z
//   .object({
//     baseToken: z.string(),
//     vaultSharesToken: z.string(),
//     minimumShareReserves: z.bigint(),
//     minimumTransactionAmount: z.bigint(),
//     positionDuration: z.bigint(),
//     checkpointDuration: z.bigint(),
//     timeStretch: z.bigint(),
//     governance: z.string(),
//     feeCollector: z.string(),
//     sweepCollector: z.string(),
//     fees: z.object({
//       curve: z.bigint(),
//       flat: z.bigint(),
//       governanceLP: z.bigint(),
//       governanceZombie: z.bigint(),
//     }),
//   })
//   .transform((v) => ({
//     ...v,
//     fees: {
//       ...v.fees,
//       // flat fee needs to be adjusted to a yearly basis
//       flat:
//         v.fees.flat /
//         (BigInt(dayjs.duration(365, "days").asSeconds()) / v.positionDuration),
//     },
//   }));

// let Targets = buildModule("ERC4626Targets", (m) => {
//   const factory = m.contractAt("HyperdriveFactory", m.getParameter("factory"));
//   m.call(
//     factory,
//     "deployTarget",
//     [
//       m.getParameter("deploymentId"),
//       m.getParameter("coordinator"),
//       m.getParameter("poolDeployConfig"),
//       "0x",
//       m.getParameter("fixedAPR"),
//       m.getParameter("timestretchAPR"),
//       0n,
//       m.getParameter("salt"),
//     ],
//     { id: "t0" },
//   );
//   m.call(
//     factory,
//     "deployTarget",
//     [
//       m.getParameter("deploymentId"),
//       m.getParameter("coordinator"),
//       m.getParameter("poolDeployConfig"),
//       "0x",
//       m.getParameter("fixedAPR"),
//       m.getParameter("timestretchAPR"),
//       1n,
//       m.getParameter("salt"),
//     ],
//     { id: "t1" },
//   );
//   m.call(
//     factory,
//     "deployTarget",
//     [
//       m.getParameter("deploymentId"),
//       m.getParameter("coordinator"),
//       m.getParameter("poolDeployConfig"),
//       "0x",
//       m.getParameter("fixedAPR"),
//       m.getParameter("timestretchAPR"),
//       2n,
//       m.getParameter("salt"),
//     ],
//     { id: "t2" },
//   );
//   m.call(
//     factory,
//     "deployTarget",
//     [
//       m.getParameter("deploymentId"),
//       m.getParameter("coordinator"),
//       m.getParameter("poolDeployConfig"),
//       "0x",
//       m.getParameter("fixedAPR"),
//       m.getParameter("timestretchAPR"),
//       3n,
//       m.getParameter("salt"),
//     ],
//     { id: "t3" },
//   );
//   m.call(
//     factory,
//     "deployTarget",
//     [
//       m.getParameter("deploymentId"),
//       m.getParameter("coordinator"),
//       m.getParameter("poolDeployConfig"),
//       "0x",
//       m.getParameter("fixedAPR"),
//       m.getParameter("timestretchAPR"),
//       4n,
//       m.getParameter("salt"),
//     ],
//     { id: "t4" },
//   );
//   const coordinator = m.contractAt(
//     "HyperdriveDeployerCoordinator",
//     m.getParameter("coordinator"),
//   );
//   const r = m.staticCall(coordinator, "deployments", [
//     m.getParameter("deploymentId"),
//   ]);
//   // const target1 = m.staticCall(
//   //   coordinator,
//   //   "deployments",
//   //   [m.getParameter("deploymentId")],
//   //   5,
//   //   { id: "c1" },
//   // );
//   // const target2 = m.staticCall(
//   //   coordinator,
//   //   "deployments",
//   //   [m.getParameter("deploymentId")],
//   //   6,
//   //   { id: "c2" },
//   // );
//   // const target3 = m.staticCall(
//   //   coordinator,
//   //   "deployments",
//   //   [m.getParameter("deploymentId")],
//   //   7,
//   //   { id: "c3" },
//   // );
//   // const target4 = m.staticCall(
//   //   coordinator,
//   //   "deployments",
//   //   [m.getParameter("deploymentId")],
//   //   8,
//   //   { id: "c4" },
//   // );

//   return {
//     r,
//     // target0: m.contractAt("ERC4626Target0", target0),
//     // target1: m.contractAt("ERC4626Target1", target1),
//     // target2: m.contractAt("ERC4626Target2", target2),
//     // target3: m.contractAt("ERC4626Target3", target3),
//     // target4: m.contractAt("ERC4626Target4", target4),
//   };
// });

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
      let coordinatorAddress = (
        await deployments.get("ERC4626HyperdriveDeployerCoordinator")
      ).address as `0x${string}`;
      let coordinator = await viem.getContractAt(
        "ERC4626HyperdriveDeployerCoordinator",
        coordinatorAddress,
      );

      // Deploy mock assets if baseToken and vaultSharesToken are left unspecified
      if (
        !config.poolDeployConfig.baseToken?.length &&
        !config.poolDeployConfig.vaultSharesToken?.length
      ) {
        // deploy base token
        let baseTokenName = name + "_BASE";
        console.log("deploying mock baseToken...");
        // NOTE: letructor args have to be specified inline due to viem's type inferencing.
        let baseToken = await viem.deployContract("ERC20Mintable", [
          baseTokenName,
          baseTokenName,
          18,
          admin as `0x${string}`,
          true,
          parseEther("10000"),
        ]);
        await deployments.save(baseTokenName, baseToken);
        await run("deploy:verify", {
          name: baseTokenName,
        });
        config.poolDeployConfig.baseToken = baseToken.address;
        await baseToken.write.approve([
          coordinatorAddress,
          config.contribution,
        ]);
        // deploy shares token
        let vaultSharesTokenName = name + "_SHARES";
        console.log("deploying mock vaultSharesToken...");
        // NOTE: letructor args have to be specified inline due to viem's type inferencing.
        let vaultSharesToken = await viem.deployContract("MockERC4626", [
          baseToken.address,
          vaultSharesTokenName,
          vaultSharesTokenName,
          parseEther("0.13"),
          admin as `0x${string}`,
          true,
          parseEther("10000"),
        ]);
        await deployments.save(vaultSharesTokenName, vaultSharesToken);
        await run("deploy:verify", {
          name: vaultSharesTokenName,
        });
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
