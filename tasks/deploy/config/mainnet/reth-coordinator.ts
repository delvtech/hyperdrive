import { HyperdriveCoordinatorConfig, MAINNET_RETH_ADDRESS } from "../../lib";
import { MAINNET_FACTORY_NAME } from "./factory";

export const MAINNET_RETH_COORDINATOR_NAME =
    "ElementDAO rETH Hyperdrive Deployer Coordinator";
export const MAINNET_RETH_COORDINATOR: HyperdriveCoordinatorConfig<"RETH"> = {
    name: MAINNET_RETH_COORDINATOR_NAME,
    prefix: "RETH",
    factoryAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(MAINNET_FACTORY_NAME).address,
    targetCount: 5,
    token: MAINNET_RETH_ADDRESS,
};
