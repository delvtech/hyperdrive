import { HyperdriveCoordinatorConfig } from "../../lib";

export const MAINNET_FORK_ERC4626_COORDINATOR: HyperdriveCoordinatorConfig<"ERC4626"> =
    {
        name: "ERC4626_COORDINATOR",
        prefix: "ERC4626",
        targetCount: 4,
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName("FACTORY").address,
    };
