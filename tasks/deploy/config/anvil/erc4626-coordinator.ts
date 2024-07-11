import { HyperdriveCoordinatorConfig } from "../../lib";
import { ANVIL_FACTORY_NAME } from "./factory";

export const ANVIL_ERC4626_COORDINATOR: HyperdriveCoordinatorConfig<"ERC4626"> =
    {
        name: "ERC4626_COORDINATOR",
        prefix: "ERC4626",
        targetCount: 5,
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName(ANVIL_FACTORY_NAME).address,
    };
