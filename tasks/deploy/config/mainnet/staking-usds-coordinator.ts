import { HyperdriveCoordinatorConfig } from "../../lib";
import { MAINNET_FACTORY_NAME } from "./factory";

export const MAINNET_STAKING_USDS_COORDINATOR_NAME =
    "ElementDAO Staking USDS Hyperdrive Deployer Coordinator";
export const MAINNET_STAKING_USDS_COORDINATOR: HyperdriveCoordinatorConfig<"StakingUSDS"> =
    {
        name: MAINNET_STAKING_USDS_COORDINATOR_NAME,
        prefix: "StakingUSDS",
        targetCount: 5,
        extraConstructorArgs: [],
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName(MAINNET_FACTORY_NAME)
                .address,
    };
