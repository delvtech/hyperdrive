import { HyperdriveCoordinatorConfig } from "../../lib";
import { GNOSIS_FACTORY_NAME } from "./factory";

export const GNOSIS_CHAINLINK_COORDINATOR_NAME =
    "ElementDAO Chainlink Hyperdrive Deployer Coordinator";
export const GNOSIS_CHAINLINK_COORDINATOR: HyperdriveCoordinatorConfig<"Chainlink"> =
    {
        name: GNOSIS_CHAINLINK_COORDINATOR_NAME,
        prefix: "Chainlink",
        targetCount: 5,
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName(GNOSIS_FACTORY_NAME)
                .address,
    };
