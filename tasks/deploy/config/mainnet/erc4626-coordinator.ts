import { HyperdriveCoordinatorConfig } from "../../lib";

// FIXME: Double-check this.
export const MAINNET_ERC4626_COORDINATOR_NAME =
    "ElementDAO ERC4626 Hyperdrive Deployer Coordinator";
export const MAINNET_ERC4626_COORDINATOR: HyperdriveCoordinatorConfig<"ERC4626"> =
    {
        name: MAINNET_ERC4626_COORDINATOR_NAME,
        prefix: "ERC4626",
        targetCount: 4,
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName("FACTORY").address,
    };
