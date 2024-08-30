import { HyperdriveCoordinatorConfig, RSETH_POOL_LINEA } from "../../lib";
import { LINEA_FACTORY_NAME } from "./factory";

export const LINEA_RSETH_COORDINATOR_NAME =
    "ElementDAO KelpDAO rsETH Hyperdrive Deployer Coordinator";
export const LINEA_RSETH_COORDINATOR: HyperdriveCoordinatorConfig<"RsETHLinea"> =
    {
        name: LINEA_RSETH_COORDINATOR_NAME,
        prefix: "RsETHLinea",
        targetCount: 5,
        extraConstructorArgs: [RSETH_POOL_LINEA],
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName(LINEA_FACTORY_NAME).address,
        token: RSETH_POOL_LINEA,
    };
