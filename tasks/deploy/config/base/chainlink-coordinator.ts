import { HyperdriveCoordinatorConfig } from "../../lib";
import { BASE_FACTORY_NAME } from "./factory";

export const BASE_CHAINLINK_COORDINATOR_NAME =
    "ElementDAO Chainlink Hyperdrive Deployer Coordinator";
export const BASE_CHAINLINK_COORDINATOR: HyperdriveCoordinatorConfig<"Chainlink"> =
    {
        name: BASE_CHAINLINK_COORDINATOR_NAME,
        prefix: "Chainlink",
        targetCount: 5,
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName(BASE_FACTORY_NAME).address,
    };
