import { HyperdriveCoordinatorConfig } from "../../lib";
import { BASE_FACTORY_NAME } from "./factory";

export const BASE_AERODROME_LP_COORDINATOR_NAME =
    "ElementDAO Aerodrome LP Hyperdrive Deployer Coordinator";
export const BASE_AERODROME_LP_COORDINATOR: HyperdriveCoordinatorConfig<"AerodromeLp"> =
    {
        name: BASE_AERODROME_LP_COORDINATOR_NAME,
        prefix: "AerodromeLp",
        targetCount: 5,
        extraConstructorArgs: [],
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName(BASE_FACTORY_NAME).address,
    };
