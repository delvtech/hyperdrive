import { parseEther } from "viem";
import { HyperdriveFactoryConfig, parseDuration } from "../../lib";

export const SEPOLIA_FACTORY: HyperdriveFactoryConfig = {
    name: "FACTORY",
    prepare: async (hre, options) => {
        await hre.hyperdriveDeploy.ensureDeployed(
            "LINKER_FACTORY",
            "ERC20ForwarderFactory",
            [],
            options,
        );
    },
    constructorArguments: async (hre) => [
        {
            governance: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
            deployerCoordinatorManager:
                "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
            hyperdriveGovernance: "0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b",
            defaultPausers: ["0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b"],
            feeCollector: "0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b",
            sweepCollector: "0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b",
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
            linkerFactory:
                hre.hyperdriveDeploy.deployments.byName("LINKER_FACTORY")
                    .address,
            linkerCodeHash: await (
                await hre.viem.getContractAt(
                    "ERC20ForwarderFactory",
                    hre.hyperdriveDeploy.deployments.byName("LINKER_FACTORY")
                        .address,
                )
            ).read.ERC20LINK_HASH(),
        },
        "FACTORY",
    ],
};
