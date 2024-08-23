import { HyperdriveCoordinatorConfig, LINEA_X_RENZO_DEPOSIT } from "../../lib";
import { LINEA_FACTORY_NAME } from "./factory";

export const LINEA_EZETH_COORDINATOR_NAME =
    "ElementDAO Renzo xezETH Hyperdrive Deployer Coordinator";
export const LINEA_EZETH_COORDINATOR: HyperdriveCoordinatorConfig<"EzETHLinea"> =
    {
        name: LINEA_EZETH_COORDINATOR_NAME,
        prefix: "EzETHLinea",
        targetCount: 5,
        extraConstructorArgs: [LINEA_X_RENZO_DEPOSIT],
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName(LINEA_FACTORY_NAME).address,
        token: LINEA_X_RENZO_DEPOSIT,
    };
