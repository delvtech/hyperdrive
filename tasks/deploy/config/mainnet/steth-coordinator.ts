import { HyperdriveCoordinatorConfig, MAINNET_STETH_ADDRESS } from "../../lib";

// FIXME: What will the name of this be.
export const MAINNET_STETH_COORDINATOR: HyperdriveCoordinatorConfig<"StETH"> = {
    name: "STETH_COORDINATOR",
    prefix: "StETH",
    factoryAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName("FACTORY").address,
    targetCount: 4,
    token: MAINNET_STETH_ADDRESS,
};
