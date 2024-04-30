import { task, types } from "hardhat/config";
import dayjs from "dayjs";
import duration, { DurationUnitType } from "dayjs/plugin/duration";
dayjs.extend(duration);
import { readFile } from "fs/promises";
import { Prettify, zAddress, zDuration, zEther } from "./utils";
import { z } from "zod";
import util from "util";

// Schema for HyperdriveFactory configuration read from hardhat config
export let zFactoryDeployConfig = z.object({
  governance: zAddress,
  hyperdriveGovernance: zAddress,
  defaultPausers: zAddress.array(),
  feeCollector: zAddress,
  sweepCollector: zAddress,
  checkpointDurationResolution: zDuration,
  minCheckpointDuration: zDuration,
  maxCheckpointDuration: zDuration,
  minPositionDuration: zDuration,
  maxPositionDuration: zDuration,
  minFixedAPR: zEther,
  maxFixedAPR: zEther,
  minTimeStretchAPR: zEther,
  maxTimeStretchAPR: zEther,
  minFees: z.object({
    curve: zEther,
    flat: zEther,
    governanceLP: zEther,
    governanceZombie: zEther,
  }),
  maxFees: z.object({
    curve: zEther,
    flat: zEther,
    governanceLP: zEther,
    governanceZombie: zEther,
  }),
});

export type FactoryDeployConfigInput = z.input<typeof zFactoryDeployConfig>;
export type FactoryDeployConfig = z.infer<typeof zFactoryDeployConfig>;

// Solidity representation of the config that is passed as a letructor argument to the HyperdriveFactory
export type HyperdriveFactoryConfig = Prettify<
  FactoryDeployConfig & {
    linkerFactory: `0x${string}`;
    linkerCodeHash: `0x${string}`;
  }
>;

export type DeployFactoryParams = {
  overwrite?: boolean;
};

task("deploy:factory", "deploys the hyperdrive factory to the configured chain")
  .addOptionalParam(
    "overwrite",
    "overwrite deployment artifacts if they exist",
    false,
    types.boolean,
  )
  .setAction(
    async (
      { overwrite }: DeployFactoryParams,
      { deployments, run, network, viem, config: hardhatConfig },
    ) => {
      const contractName = "HyperdriveFactory";
      // Skip if deployed and overwrite=false.
      let artifacts = await deployments.all();
      if (!overwrite && artifacts[contractName]) {
        console.log(`${contractName} already deployed`);
        return;
      }
      // Read and parse the provided configuration file
      let config = hardhatConfig.networks[network.name].factory;

      // Get the address and codehash for the forwarder factory
      let forwarderAddress = (await deployments.get("ERC20ForwarderFactory"))
        .address;
      let forwarder = await viem.getContractAt(
        "ERC20ForwarderFactory",
        forwarderAddress as `0x${string}`,
      );

      // Construct the factory configuration object
      console.log("deploying HyperdriveFactory...");
      let factoryConfig = {
        ...config,
        linkerFactory: forwarder.address,
        linkerCodeHash: await forwarder.read.ERC20LINK_HASH(),
      };

      // Deploy the contract, save the artifact, and verify.
      let hyperdriveFactory = await viem.deployContract(contractName, [
        factoryConfig,
        `factory_${network.name}`,
      ]);
      await deployments.save(contractName, {
        ...hyperdriveFactory,
        args: [factoryConfig, `factory_${network.name}`],
      });
      await run("deploy:verify", { name: contractName });
    },
  );
