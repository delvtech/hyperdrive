import { HyperdriveFactoryDeployConfigInput } from "../../lib";

export const SEPOLIA_FACTORY: HyperdriveFactoryDeployConfigInput = {
    name: "FACTORY",
    governance: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
    hyperdriveGovernance: "0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b",
    defaultPausers: ["0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b"],
    feeCollector: "0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b",
    sweepCollector: "0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b",
    checkpointDurationResolution: "8 hours",
    minCheckpointDuration: "24 hours",
    maxCheckpointDuration: "24 hours",
    minPositionDuration: "7 days",
    maxPositionDuration: "365 days",
    minFixedAPR: "0.01",
    maxFixedAPR: "0.6",
    minTimeStretchAPR: "0.01",
    maxTimeStretchAPR: "0.6",
    minCircuitBreakerDelta: "0.5",
    maxCircuitBreakerDelta: "1",
    minFees: {
        curve: "0.001",
        flat: "0.0001",
        governanceLP: "0.15",
        governanceZombie: "0.03",
    },
    maxFees: {
        curve: "0.05",
        flat: "0.005",
        governanceLP: "0.15",
        governanceZombie: "0.03",
    },
};
