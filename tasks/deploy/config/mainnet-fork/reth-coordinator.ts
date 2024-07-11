import { HyperdriveCoordinatorConfig, MAINNET_RETH_ADDRESS } from "../../lib";
import { MAINNET_FORK_FACTORY_NAME } from "./factory";

export const MAINNET_FORK_RETH_COORDINATOR_NAME = "RETH_COORDINATOR";
export const MAINNET_FORK_RETH_COORDINATOR: HyperdriveCoordinatorConfig<"RETH"> =
    {
        name: "RETH_COORDINATOR",
        prefix: "RETH",
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName(MAINNET_FORK_FACTORY_NAME)
                .address,
        targetCount: 5,
        token: MAINNET_RETH_ADDRESS,
    };
