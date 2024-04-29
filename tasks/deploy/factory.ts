import { task, types } from "hardhat/config";
import dayjs from "dayjs";
import duration, { DurationUnitType } from "dayjs/plugin/duration";
dayjs.extend(duration);
import { readFile } from "fs/promises";
import { parseEther } from "viem";

// All strings here will be parsed as bigints.
// Durations will use dayjs to convert from time periods to number of seconds
export type FactoryDeployConfig = {
  governance: `0x${string}`;
  hyperdriveGovernance: `0x${string}`;
  defaultPausers: `0x${string}`[];
  feeCollector: `0x${string}`;
  sweepCollector: `0x${string}`;
  checkpointDurationResolution: string;
  minCheckpointDuration: string;
  maxCheckpointDuration: string;
  minPositionDuration: string;
  maxPositionDuration: string;
  minFixedAPR: string;
  maxFixedAPR: string;
  minTimeStretchAPR: string;
  maxTimeStretchAPR: string;
  minFees: {
    curve: string;
    flat: string;
    governanceLP: string;
    governanceZombie: string;
  };
  maxFees: {
    curve: string;
    flat: string;
    governanceLP: string;
    governanceZombie: string;
  };
};

export type HyperdriveFactoryConfig = {
  governance: `0x${string}`;
  hyperdriveGovernance: `0x${string}`;
  defaultPausers: `0x${string}`[];
  feeCollector: `0x${string}`;
  sweepCollector: `0x${string}`;
  checkpointDurationResolution: bigint;
  minCheckpointDuration: bigint;
  maxCheckpointDuration: bigint;
  minPositionDuration: bigint;
  maxPositionDuration: bigint;
  minFixedAPR: bigint;
  maxFixedAPR: bigint;
  minTimeStretchAPR: bigint;
  maxTimeStretchAPR: bigint;
  minFees: {
    curve: bigint;
    flat: bigint;
    governanceLP: bigint;
    governanceZombie: bigint;
  };
  maxFees: {
    curve: bigint;
    flat: bigint;
    governanceLP: bigint;
    governanceZombie: bigint;
  };
  linkerFactory: `0x${string}`;
  linkerCodeHash: `0x${string}`;
};

const parseDuration = (d: string) => {
  const [quantityString, unit] = d.split(" ");
  return dayjs
    .duration(parseInt(quantityString), unit as DurationUnitType)
    .asSeconds();
};

task("deploy:factory", "deploys the hyperdrive factory to the configured chain")
  .addParam(
    "configFile",
    "factory configuration file",
    undefined,
    types.inputFile,
  )
  .setAction(
    async (
      { configFile }: { configFile: string },
      { deployments, run, network, viem },
    ) => {
      // Read and parse the provided configuration file
      const configBuffer = await readFile(configFile);
      const config = JSON.parse(configBuffer.toString()) as FactoryDeployConfig;

      // Deploy the ERC20ForwarderFactory
      console.log("deploying ERC20ForwarderFactory...");
      const linkerFactory = await viem.deployContract(
        "ERC20ForwarderFactory",
        [],
      );
      await deployments.save("ERC20ForwarderFactory", linkerFactory);
      await run("verify:verify", {
        address: linkerFactory.address,
        constructorArguments: [],
        network: network.name,
      });

      // Construct the factory configuration object and deploy the HyperdriveFactory
      console.log("deploying HyperdriveFactory...");
      const factoryConfig = {
        governance: config.governance,
        hyperdriveGovernance: config.hyperdriveGovernance,
        defaultPausers: config.defaultPausers,
        feeCollector: config.feeCollector,
        sweepCollector: config.sweepCollector,
        checkpointDurationResolution: BigInt(
          parseDuration(config.checkpointDurationResolution),
        ),
        minCheckpointDuration: BigInt(
          parseDuration(config.minCheckpointDuration),
        ),
        maxCheckpointDuration: BigInt(
          parseDuration(config.maxCheckpointDuration),
        ),
        minPositionDuration: BigInt(parseDuration(config.minPositionDuration)),
        maxPositionDuration: BigInt(parseDuration(config.maxPositionDuration)),
        minFixedAPR: parseEther(config.minFixedAPR),
        maxFixedAPR: parseEther(config.maxFixedAPR),
        minTimeStretchAPR: parseEther(config.minTimeStretchAPR),
        maxTimeStretchAPR: parseEther(config.maxTimeStretchAPR),
        minFees: {
          curve: parseEther(config.minFees.curve),
          flat: parseEther(config.minFees.flat),
          governanceLP: parseEther(config.minFees.governanceLP),
          governanceZombie: parseEther(config.minFees.governanceZombie),
        },
        maxFees: {
          curve: parseEther(config.maxFees.curve),
          flat: parseEther(config.maxFees.flat),
          governanceLP: parseEther(config.maxFees.governanceLP),
          governanceZombie: parseEther(config.maxFees.governanceZombie),
        },
        linkerFactory: linkerFactory.address,
        linkerCodeHash: await linkerFactory.read.ERC20LINK_HASH(),
      };
      console.log("factoryConfig", factoryConfig);
      const hyperdriveFactory = await viem.deployContract("HyperdriveFactory", [
        factoryConfig,
        `factory-${network.name}`,
      ]);
      await deployments.save("HyperdriveFactory", hyperdriveFactory);
      await run("verify:verify", {
        address: hyperdriveFactory.address,
        constructorArguments: [factoryConfig, `factory-${network.name}`],
        network: network.name,
      });
    },
  );
