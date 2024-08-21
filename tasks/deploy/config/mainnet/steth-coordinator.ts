import { HyperdriveCoordinatorConfig, STETH_ADDRESS_MAINNET } from "../../lib";
import { MAINNET_FACTORY_NAME } from "./factory";

export const MAINNET_STETH_COORDINATOR_NAME =
    "ElementDAO stETH Hyperdrive Deployer Coordinator";
export const MAINNET_STETH_COORDINATOR: HyperdriveCoordinatorConfig<"StETH"> = {
    name: MAINNET_STETH_COORDINATOR_NAME,
    prefix: "StETH",
    factoryAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(MAINNET_FACTORY_NAME).address,
    targetCount: 5,
    token: STETH_ADDRESS_MAINNET,
};
