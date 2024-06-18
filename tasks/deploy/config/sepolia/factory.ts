import { Address, parseEther } from "viem";
import { HyperdriveFactoryConfig, parseDuration } from "../../lib";
import { SEPOLIA_CHECKPOINT_REWARDER_NAME } from "./checkpoint-rewarder";

export const SEPOLIA_FACTORY_NAME = "FACTORY";
export const SEPOLIA_FACTORY_FORWARDER_NAME = "FACTORY_FORWARDER";
export const SEPOLIA_FACTORY_GOVERNANCE_ADDRESS =
    "0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b";

export const SEPOLIA_FACTORY: HyperdriveFactoryConfig = {
    name: SEPOLIA_FACTORY_NAME,
    prepare: async (hre, options) => {
        await hre.hyperdriveDeploy.ensureDeployed(
            SEPOLIA_FACTORY_FORWARDER_NAME,
            "ERC20ForwarderFactory",
            [SEPOLIA_FACTORY_FORWARDER_NAME],
            options,
        );
    },
    constructorArguments: async (hre) => [
        {
            governance: SEPOLIA_FACTORY_GOVERNANCE_ADDRESS,
            deployerCoordinatorManager: (await hre.getNamedAccounts())[
                "deployer"
            ] as Address,
            hyperdriveGovernance: SEPOLIA_FACTORY_GOVERNANCE_ADDRESS,
            defaultPausers: [
                (await hre.getNamedAccounts())["deployer"] as Address,
            ],
            feeCollector: SEPOLIA_FACTORY_GOVERNANCE_ADDRESS,
            sweepCollector: SEPOLIA_FACTORY_GOVERNANCE_ADDRESS,
            checkpointRewarder: hre.hyperdriveDeploy.deployments.byName(
                SEPOLIA_CHECKPOINT_REWARDER_NAME,
            ).address,
            checkpointDurationResolution: parseDuration("8 hours"),
            minCheckpointDuration: parseDuration("24 hours"),
            maxCheckpointDuration: parseDuration("24 hours"),
            minPositionDuration: parseDuration("7 days"),
            maxPositionDuration: parseDuration("365 days"),
            minFixedAPR: parseEther("0.01"),
            maxFixedAPR: parseEther("0.6"),
            minTimeStretchAPR: parseEther("0.01"),
            maxTimeStretchAPR: parseEther("0.6"),
            minCircuitBreakerDelta: parseEther("0.5"),
            maxCircuitBreakerDelta: parseEther("1"),
            minFees: {
                curve: parseEther("0.001"),
                flat: parseEther("0.0001"),
                governanceLP: parseEther("0.15"),
                governanceZombie: parseEther("0.03"),
            },
            maxFees: {
                curve: parseEther("0.05"),
                flat: parseEther("0.005"),
                governanceLP: parseEther("0.15"),
                governanceZombie: parseEther("0.03"),
            },
            linkerFactory: hre.hyperdriveDeploy.deployments.byName(
                SEPOLIA_FACTORY_FORWARDER_NAME,
            ).address,
            linkerCodeHash: await (
                await hre.viem.getContractAt(
                    "ERC20ForwarderFactory",
                    hre.hyperdriveDeploy.deployments.byName(
                        SEPOLIA_FACTORY_FORWARDER_NAME,
                    ).address,
                )
            ).read.ERC20LINK_HASH(),
        },
        SEPOLIA_FACTORY_NAME,
    ],
};
