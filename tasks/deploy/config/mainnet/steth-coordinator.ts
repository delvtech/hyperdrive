import { HyperdriveCoordinatorConfig, MAINNET_STETH_ADDRESS } from "../../lib";

export const MAINNET_STETH_COORDINATOR_NAME =
    "ElementDAO stETH Hyperdrive Deployer Coordinator";
export const MAINNET_STETH_COORDINATOR: HyperdriveCoordinatorConfig<"StETH"> = {
    name: MAINNET_STETH_COORDINATOR_NAME,
    prefix: "StETH",
    factoryAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName("FACTORY").address,
    targetCount: 4,
    token: MAINNET_STETH_ADDRESS,
};
