import { HyperdriveCoordinatorConfig } from "../../lib";
import { BASE_FACTORY_NAME } from "./factory";

export const BASE_STK_WELL_COORDINATOR_NAME =
    "ElementDAO Moonwell StkWell Hyperdrive Deployer Coordinator";
export const BASE_STK_WELL_COORDINATOR: HyperdriveCoordinatorConfig<"StkWell"> =
    {
        name: BASE_STK_WELL_COORDINATOR_NAME,
        prefix: "StkWell",
        targetCount: 5,
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName(BASE_FACTORY_NAME).address,
    };
