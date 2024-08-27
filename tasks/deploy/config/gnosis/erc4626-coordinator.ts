import { HyperdriveCoordinatorConfig } from "../../lib";
import { GNOSIS_FACTORY_NAME } from "./factory";

export const GNOSIS_ERC4626_COORDINATOR_NAME =
    "ElementDAO ERC4626 Hyperdrive Deployer Coordinator";
export const GNOSIS_ERC4626_COORDINATOR: HyperdriveCoordinatorConfig<"ERC4626"> =
    {
        name: GNOSIS_ERC4626_COORDINATOR_NAME,
        prefix: "ERC4626",
        targetCount: 5,
        factoryAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName(GNOSIS_FACTORY_NAME)
                .address,
    };
