import { HyperdriveCoordinatorConfig } from "../../lib";

// FIXME: What will the name of this contract be?
export const MAINNET_ERC4626_COORDINATOR: HyperdriveCoordinatorConfig<"ERC4626"> =
    {
        name: "ERC4626_COORDINATOR",
        prefix: "ERC4626",
        targetCount: 4,
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName("FACTORY").address,
    };
