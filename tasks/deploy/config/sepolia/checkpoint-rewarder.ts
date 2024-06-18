import { HyperdriveCheckpointRewarderConfig } from "../../lib";

export const SEPOLIA_CHECKPOINT_REWARDER_NAME = "CHECKPOINT_REWARDER";

export const SEPOLIA_CHECKPOINT_REWARDER: HyperdriveCheckpointRewarderConfig = {
    name: SEPOLIA_CHECKPOINT_REWARDER_NAME,
    constructorArguments: [
        SEPOLIA_CHECKPOINT_REWARDER_NAME,
        "0x0000000000000000000000000000000000000000",
    ],
};
