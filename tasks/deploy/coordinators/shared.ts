import { subtask, types } from "hardhat/config";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { validHyperdrivePrefixes } from "../utils";
dayjs.extend(duration);

export type DeployCoordinatorsBaseParams = {
  prefix: keyof typeof validHyperdrivePrefixes;
};

/**
 * Deploys the core deployer and all targets for a deployer coordinator
 * - Unfortunately, by parameterizing the contract names we lose some type-checking ability
 */
subtask(
  "deploy:coordinators:shared",
  "shared deployment steps for deployer coordinators",
)
  .addParam(
    "prefix",
    "contract prefix for the coordinator",
    undefined,
    types.string,
  )
  .setAction(
    async (
      { prefix }: DeployCoordinatorsBaseParams,
      { deployments, run, viem },
    ) => {
      let prefixValue = validHyperdrivePrefixes[prefix];
      // Deploy the core deployer
      console.log(`deploying ${prefixValue}HyperdriveCoreDeployer...`);
      let core = await viem.deployContract(
        `${prefixValue}HyperdriveCoreDeployer` as any,
      );
      await deployments.save(`${prefixValue}HyperdriveCoreDeployer`, {
        ...core,
        args: [],
      } as any);
      await run("deploy:verify", {
        name: `${prefixValue}HyperdriveCoreDeployer`,
      });

      // Deploy the targets
      let targets: `0x${string}`[] = [];
      for (let i = 0; i < 5; i++) {
        console.log(`deploying ${prefixValue}Target${i}Deployer...`);
        let contract = await viem.deployContract(
          `${prefixValue}Target${i}Deployer`,
        );
        targets.push(contract.address);
        await deployments.save(`${prefixValue}Target${i}Deployer`, {
          ...contract,
          args: [],
        } as any);
        await run("deploy:verify", {
          name: `${prefixValue}Target${i}Deployer`,
        });
      }
    },
  );
