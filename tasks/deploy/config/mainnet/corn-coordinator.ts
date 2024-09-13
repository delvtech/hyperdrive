import {
    CORN_SILO_ADDRESS_MAINNET,
    HyperdriveCoordinatorConfig,
} from "../../lib";
import { MAINNET_FACTORY_NAME } from "./factory";

export const MAINNET_CORN_COORDINATOR_NAME =
    "ElementDAO Corn Hyperdrive Deployer Coordinator";
export const MAINNET_CORN_COORDINATOR: HyperdriveCoordinatorConfig<"Corn"> = {
    name: MAINNET_CORN_COORDINATOR_NAME,
    prefix: "Corn",
    targetCount: 5,
    extraConstructorArgs: [CORN_SILO_ADDRESS_MAINNET],
    factoryAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(MAINNET_FACTORY_NAME).address,
    token: CORN_SILO_ADDRESS_MAINNET,
};
