import { HyperdriveCoordinatorConfig } from "../../lib";
import { MAINNET_FACTORY_NAME } from "./factory";

export const MAINNET_ERC4626_COORDINATOR_NAME =
    "ElementDAO ERC4626 Hyperdrive Deployer Coordinator";
export const MAINNET_ERC4626_COORDINATOR: HyperdriveCoordinatorConfig<"ERC4626"> =
    {
        name: MAINNET_ERC4626_COORDINATOR_NAME,
        prefix: "ERC4626",
        targetCount: 5,
        extraConstructorArgs: [],
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName(MAINNET_FACTORY_NAME)
                .address,
    };
