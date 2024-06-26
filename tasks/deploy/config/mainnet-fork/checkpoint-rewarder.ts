import { HyperdriveCheckpointRewarderConfig } from "../../lib";

export const MAINNET_FORK_CHECKPOINT_REWARDER_NAME = "CHECKPOINT_REWARDER";

export const MAINNET_FORK_CHECKPOINT_REWARDER: HyperdriveCheckpointRewarderConfig =
    {
        name: MAINNET_FORK_CHECKPOINT_REWARDER_NAME,
        constructorArguments: [
            MAINNET_FORK_CHECKPOINT_REWARDER_NAME,
            "0x0000000000000000000000000000000000000000",
        ],
    };
