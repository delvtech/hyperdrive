import { HyperdriveCoordinatorConfig } from "../../lib";
import { SEPOLIA_FACTORY_NAME } from "./factory";

export const SEPOLIA_MORPHO_BLUE_COORDINATOR_NAME = "MORPHO_BLUE_COORDINATOR";

export const SEPOLIA_MORPHO_BLUE_COORDINATOR: HyperdriveCoordinatorConfig<"MorphoBlue"> =
    {
        name: SEPOLIA_MORPHO_BLUE_COORDINATOR_NAME,
        prefix: "MorphoBlue",
        targetCount: 5,
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName(SEPOLIA_FACTORY_NAME)
                .address,
    };
