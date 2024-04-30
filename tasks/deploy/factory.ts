import { task, types } from "hardhat/config";
import dayjs from "dayjs";
import duration, { DurationUnitType } from "dayjs/plugin/duration";
dayjs.extend(duration);
import { readFile } from "fs/promises";
import { Prettify, zAddress, zDuration, zEther } from "./utils";
import { z } from "zod";
import util from "util";

// Schema for HyperdriveFactory configuration to be read in from a JSON file
export const zFactoryDeployConfig = z.object({
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

// Solidity representation of the config that is passed as a constructor argument to the HyperdriveFactory
export type HyperdriveFactoryConfig = Prettify<
  FactoryDeployConfig & {
    linkerFactory: `0x${string}`;
    linkerCodeHash: `0x${string}`;
  }
>;

export type DeployFactoryParams = {};

task(
  "deploy:factory",
  "deploys the hyperdrive factory to the configured chain",
).setAction(
  async (
    {}: DeployFactoryParams,
    { deployments, run, network, viem, config: hardhatConfig },
  ) => {
    // Read and parse the provided configuration file
    const config = hardhatConfig.networks[network.name].factory;

    console.log(util.inspect(config, false, null, true /* enable colors */));

    // Get the address and codehash for the forwarder factory
    console.log("reading ERC20ForwarderFactory code hash...");
    const forwarderAddress = (await deployments.get("ERC20ForwarderFactory"))
      .address;
    const forwarder = await viem.getContractAt(
      "ERC20ForwarderFactory",
      forwarderAddress as `0x${string}`,
    );

    // Construct the factory configuration object and deploy the HyperdriveFactory
    console.log("deploying HyperdriveFactory...");
    const factoryConfig = {
      ...config,
      linkerFactory: forwarder.address,
      linkerCodeHash: await forwarder.read.ERC20LINK_HASH(),
    };
    const hyperdriveFactory = await viem.deployContract("HyperdriveFactory", [
      factoryConfig,
      `factory-${network.name}`,
    ]);
    await deployments.save("HyperdriveFactory", hyperdriveFactory);
    if (network.name != "hardhat")
      await run("verify:verify", {
        address: hyperdriveFactory.address,
        constructorArguments: [factoryConfig, `factory-${network.name}`],
        network: network.name,
      });
  },
);
