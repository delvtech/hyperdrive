import { HyperdriveCoordinatorConfig, MAINNET_STETH_ADDRESS } from "../../lib";
import { MAINNET_FORK_FACTORY_NAME } from "./factory";

export const MAINNET_FORK_STETH_COORDINATOR_NAME = "STETH_COORDINATOR";
export const MAINNET_FORK_STETH_COORDINATOR: HyperdriveCoordinatorConfig<"StETH"> =
    {
        name: "STETH_COORDINATOR",
        prefix: "StETH",
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName(MAINNET_FORK_FACTORY_NAME)
                .address,
        targetCount: 5,
        token: MAINNET_STETH_ADDRESS,
    };
