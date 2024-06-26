import { HyperdriveCoordinatorConfig, MAINNET_RETH_ADDRESS } from "../../lib";

export const MAINNET_FORK_RETH_COORDINATOR_NAME = "RETH_COORDINATOR";
export const MAINNET_FORK_RETH_COORDINATOR: HyperdriveCoordinatorConfig<"RETH"> =
    {
        name: "RETH_COORDINATOR",
        prefix: "RETH",
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName("FACTORY").address,
        targetCount: 4,
        token: MAINNET_RETH_ADDRESS,
    };
