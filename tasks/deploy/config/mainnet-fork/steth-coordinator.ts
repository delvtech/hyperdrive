import { HyperdriveCoordinatorConfig, MAINNET_STETH_ADDRESS } from "../../lib";

export const MAINNET_FORK_STETH_COORDINATOR_NAME = "STETH_COORDINATOR";
export const MAINNET_FORK_STETH_COORDINATOR: HyperdriveCoordinatorConfig<"StETH"> =
    {
        name: "STETH_COORDINATOR",
        prefix: "StETH",
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName("FACTORY").address,
        targetCount: 4,
        token: MAINNET_STETH_ADDRESS,
    };
