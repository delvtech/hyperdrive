import { task, types } from "hardhat/config";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { z } from "zod";
import {
  DeployInstanceParams,
  PoolConfig,
  PoolDeployConfig,
  zInstanceDeployConfig,
} from "./schema";

dayjs.extend(duration);

// Set the base token to always be the ETH letant.
export let zStETHInstanceDeployConfig = zInstanceDeployConfig
  .transform((v) => ({
    ...v,
    poolDeployConfig: {
      ...v.poolDeployConfig,
      baseToken: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE" as `0x${string}`,
    },
  }))
  .superRefine((v, c) => {
    // Contribution via the base token (ETH) are not allowed for StETH.
    if (v.options.asBase) {
      c.addIssue({
        code: z.ZodIssueCode.custom,
        message:
          "`options.asBase` must be set to false for StETH Hyperdrive instances.",
        path: ["options.asBase"],
      });
    }
  });

export type StETHInstanceDeployConfigInput = z.input<
  typeof zStETHInstanceDeployConfig
>;
export type StETHInstanceDeployConfig = z.infer<
  typeof zStETHInstanceDeployConfig
>;

task("deploy:instances:steth", "deploys the StETH deployment coordinator")
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
      {
        deployments,
        run,
        network,
        viem,
        getNamedAccounts,
        config: hardhatConfig,
      },
    ) => {
      let artifacts = await deployments.all();
      if (!overwrite && artifacts[`${name}_StETHTarget0`]) {
        console.log(`${name}_StETHTarget0 already deployed`);
        return;
      }
      console.log(`starting hyperdrive deployment ${name}`);
      let deployer = (await getNamedAccounts())["deployer"] as `0x${string}`;
      // Read and parse the provided configuration file
      let config = hardhatConfig.networks[network.name].instances?.steth?.find(
        (i) => i.name === name,
      );
      if (!config)
        throw new Error(
          `unable to find instance for network ${network.name} with name ${name}`,
        );

      // Set 'admin' to the deployer address if not specified via param
      if (!admin?.length) admin = deployer;

      // Get the lido token address from the deployer coordinator
      let coordinatorAddress = (
        await deployments.get("StETHHyperdriveDeployerCoordinator")
      ).address as `0x${string}`;
      let coordinator = await viem.getContractAt(
        "StETHHyperdriveDeployerCoordinator",
        coordinatorAddress,
      );
      let lido = await viem.getContractAt(
        "ILido",
        await coordinator.read.lido(),
      );
      config.poolDeployConfig.vaultSharesToken = lido.address;

      // Ensure the deployer has sufficiet funds for the contribution.
      let pc = await viem.getPublicClient();
      if ((await pc.getBalance({ address: deployer })) < config.contribution)
        throw new Error("insufficient ETH balance for contribution");

      // Obtain shares for the contribution.
      await lido.write.submit([deployer], { value: config.contribution });

      // Ensure the deployer has approved the deployer coordinator for lido shares.
      let allowance = await lido.read.allowance([deployer, coordinatorAddress]);
      if (allowance < config.contribution) {
        console.log("approving coordinator for contribution...");
        await lido.write.approve([
          coordinatorAddress,
          config.contribution * 2n,
        ]);
      }

      // Deploy the targets and hyperdrive instance
      await run("deploy:instances:shared", { prefix: "steth", name });
    },
  );
