import {
    HyperdriveCoordinatorConfig,
    RENZO_RESTAKE_MANAGER_ADDRESS_MAINNET,
} from "../../lib";
import { MAINNET_FACTORY_NAME } from "./factory";

export const MAINNET_EZETH_COORDINATOR_NAME =
    "ElementDAO ezETH Hyperdrive Deployer Coordinator";
export const MAINNET_EZETH_COORDINATOR: HyperdriveCoordinatorConfig<"EzETH"> = {
    name: MAINNET_EZETH_COORDINATOR_NAME,
    prefix: "EzETH",
    targetCount: 5,
    extraConstructorArgs: [RENZO_RESTAKE_MANAGER_ADDRESS_MAINNET],
    factoryAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(MAINNET_FACTORY_NAME).address,
    token: RENZO_RESTAKE_MANAGER_ADDRESS_MAINNET,
};
