import { HyperdriveCoordinatorConfig } from "../../lib";

export const SEPOLIA_ERC4626_COORDINATOR_NAME = "ERC4626_COORDINATOR";

export const SEPOLIA_ERC4626_COORDINATOR: HyperdriveCoordinatorConfig<"ERC4626"> =
    {
        name: SEPOLIA_ERC4626_COORDINATOR_NAME,
        prefix: "ERC4626",
        targetCount: 5,
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName("FACTORY").address,
    };
