import { HyperdriveCoordinatorConfig } from "../../lib";
import { MAINNET_FACTORY_NAME } from "./factory";

export const MAINNET_MORPHO_BLUE_COORDINATOR_NAME =
    "ElementDAO MorphoBlue Hyperdrive Deployer Coordinator";

export const MAINNET_MORPHO_BLUE_COORDINATOR: HyperdriveCoordinatorConfig<"MorphoBlue"> =
    {
        name: MAINNET_MORPHO_BLUE_COORDINATOR_NAME,
        prefix: "MorphoBlue",
        targetCount: 5,
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName(MAINNET_FACTORY_NAME)
                .address,
    };
