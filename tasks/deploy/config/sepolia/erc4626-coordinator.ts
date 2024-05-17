import { HyperdriveCoordinatorConfig } from "../../lib";

export const SEPOLIA_ERC4626_COORDINATOR: HyperdriveCoordinatorConfig<"ERC4626"> =
    {
        name: "ERC4626_COORDINATOR",
        prefix: "ERC4626",
        targetCount: 4,
        extraConstructorArgs: [],
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName("FACTORY").address,
    };
