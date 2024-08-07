import { HyperdriveCoordinatorConfig } from "../../lib";
import { MAINNET_FORK_FACTORY_NAME } from "./factory";

export const MAINNET_FORK_ERC4626_COORDINATOR_NAME = "ERC4626_COORDINATOR";
export const MAINNET_FORK_ERC4626_COORDINATOR: HyperdriveCoordinatorConfig<"ERC4626"> =
    {
        name: MAINNET_FORK_ERC4626_COORDINATOR_NAME,
        prefix: "ERC4626",
        targetCount: 5,
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName(MAINNET_FORK_FACTORY_NAME)
                .address,
    };
