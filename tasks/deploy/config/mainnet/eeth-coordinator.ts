import {
    EETH_LIQUIDITY_POOL_ADDRESS_MAINNET,
    HyperdriveCoordinatorConfig,
} from "../../lib";
import { MAINNET_FACTORY_NAME } from "./factory";

export const MAINNET_EETH_COORDINATOR_NAME =
    "ElementDAO ether.fi eETH Hyperdrive Deployer Coordinator";
export const MAINNET_EETH_COORDINATOR: HyperdriveCoordinatorConfig<"EETH"> = {
    name: MAINNET_EETH_COORDINATOR_NAME,
    prefix: "EETH",
    targetCount: 5,
    extraConstructorArgs: [EETH_LIQUIDITY_POOL_ADDRESS_MAINNET],
    factoryAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(MAINNET_FACTORY_NAME).address,
    token: EETH_LIQUIDITY_POOL_ADDRESS_MAINNET,
};
