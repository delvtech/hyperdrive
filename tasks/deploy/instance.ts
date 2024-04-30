import { task, types } from "hardhat/config";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { Prettify, zAddress, zDuration, zEther } from "./utils";
import { z } from "zod";
import { readFile } from "fs/promises";
dayjs.extend(duration);

const COORDINATORS = [
  "ERC4626HyperdriveDeployerCoordinator",
  "EzETHHyperdriveDeployerCoordinator",
  "LsETHHyperdriveDeployerCoordinator",
  "RETHHyperdriveDeployerCoordinator",
  "StETHHyperdriveDeployerCoordinator",
] as const;

const CoordinatorEnum = z.enum(COORDINATORS);

type l =
  | "ERC4626HyperdriveDeployerCoordinator"
  | "EzETHHyperdriveDeployerCoordinator"
  | "LsETHHyperdriveDeployerCoordinator"
  | "RETHHyperdriveDeployerCoordinator"
  | "StETHHyperdriveDeployerCoordinator";

// Schema for hyperdrive instance configuration to be read in from a JSON file
export const zInstanceDeployConfig = z.object({
  coordinator: CoordinatorEnum,
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
});

export type InstanceDeployConfigInput = z.input<typeof zInstanceDeployConfig>;
export type InstanceDeployConfig = z.infer<typeof zInstanceDeployConfig>;

// Solidity representation of the config that is passed as a constructor argument when creating instances
export type PoolDeployConfig = Prettify<
  Omit<InstanceDeployConfig, "coordinator"> & {
    linkerFactory: `0x${string}`;
    linkerCodeHash: `0x${string}`;
  }
>;

export type DeployInstanceParams = {
  configFile: string;
};

task("deploy:instance", "deploys the ERC4626 deployment coordinator")
  .addParam("configFile", "path to the hyperdrive instance configuration file")
  .setAction(
    async (
      { configFile }: DeployInstanceParams,
      { deployments, run, network, viem, artifacts },
    ) => {
      // Read and parse the provided configuration file
      const config = zInstanceDeployConfig.parse(
        JSON.parse((await readFile(configFile)).toString()),
      );

      // Get the address for the deployer coordinator
      const coordinatorAddress = (await deployments.get(config.coordinator))
        .address;
      const coordinator = await viem.getContractAt(
        "HyperdriveDeployerCoordinator",
        coordinatorAddress as `0x${string}`,
      );

      // Get the address and codehash for the forwarder factory
      console.log("reading ERC20ForwarderFactory code hash...");
      const forwarderAddress = (await deployments.get("ERC20ForwarderFactory"))
        .address;
      const forwarder = await viem.getContractAt(
        "ERC20ForwarderFactory",
        forwarderAddress as `0x${string}`,
      );
    },
  );
