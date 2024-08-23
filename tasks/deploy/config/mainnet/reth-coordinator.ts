import { HyperdriveCoordinatorConfig, RETH_ADDRESS_MAINNET } from "../../lib";
import { MAINNET_FACTORY_NAME } from "./factory";

export const MAINNET_RETH_COORDINATOR_NAME =
    "ElementDAO rETH Hyperdrive Deployer Coordinator";
export const MAINNET_RETH_COORDINATOR: HyperdriveCoordinatorConfig<"RETH"> = {
    name: MAINNET_RETH_COORDINATOR_NAME,
    prefix: "RETH",
    factoryAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(MAINNET_FACTORY_NAME).address,
    targetCount: 5,
    token: RETH_ADDRESS_MAINNET,
};
