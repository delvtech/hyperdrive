import { HyperdriveCoordinatorConfig } from "../../lib";
import { BASE_FACTORY_NAME } from "./factory";

export const BASE_MORPHO_BLUE_COORDINATOR_NAME =
    "ElementDAO MorphoBlue Hyperdrive Deployer Coordinator";

export const BASE_MORPHO_BLUE_COORDINATOR: HyperdriveCoordinatorConfig<"MorphoBlue"> =
    {
        name: BASE_MORPHO_BLUE_COORDINATOR_NAME,
        prefix: "MorphoBlue",
        targetCount: 5,
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName(BASE_FACTORY_NAME).address,
    };
