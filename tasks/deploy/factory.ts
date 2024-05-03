import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { task, types } from "hardhat/config";
import { z } from "zod";
import { Deployments } from "./deployments";
import { DeploySaveParams } from "./save";
import { Prettify, zAddress, zDuration, zEther } from "./types";
dayjs.extend(duration);

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
            { run, network, viem, config: hardhatConfig },
        ) => {
            const contractName = "HyperdriveFactory";
            // Skip if deployed and overwrite=false.
            if (
                !overwrite &&
                Deployments.get().byNameSafe(contractName, network.name)
            ) {
                console.log(`${contractName} already deployed`);
                return;
            }

            // Read and parse the provided configuration file
            let config = hardhatConfig.networks[network.name].factory;

            // Get the address and codehash for the forwarder factory
            let forwarderAddress = (
                await Deployments.get().byName(
                    "ERC20ForwarderFactory",
                    network.name,
                )
            ).address;
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
            await run("deploy:save", {
                name: contractName,
                args: [factoryConfig, `factory_${network.name}`],
                abi: hyperdriveFactory.abi,
                address: hyperdriveFactory.address,
                contract: "HyperdriveFactory",
            } as DeploySaveParams);
        },
    );
