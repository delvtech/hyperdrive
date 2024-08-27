import { HyperdriveCoordinatorConfig, X_RENZO_DEPOSIT_LINEA } from "../../lib";
import { LINEA_FACTORY_NAME } from "./factory";

export const LINEA_EZETH_COORDINATOR_NAME =
    "ElementDAO Renzo xezETH Hyperdrive Deployer Coordinator";
export const LINEA_EZETH_COORDINATOR: HyperdriveCoordinatorConfig<"EzETHLinea"> =
    {
        name: LINEA_EZETH_COORDINATOR_NAME,
        prefix: "EzETHLinea",
        targetCount: 5,
        extraConstructorArgs: [X_RENZO_DEPOSIT_LINEA],
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName(LINEA_FACTORY_NAME).address,
        token: X_RENZO_DEPOSIT_LINEA,
    };
