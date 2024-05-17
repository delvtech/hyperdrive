import { subtask } from "hardhat/config";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployNamedTaskParams,
} from "./lib";

export type DeployRegistryParams = HyperdriveDeployNamedTaskParams;

HyperdriveDeployBaseTask(
    subtask(
        "deploy:registry",
        "deploys the hyperdrive factory to the configured chain",
    ),
).setAction(
    async ({ name, ...rest }: DeployRegistryParams, { hyperdriveDeploy }) => {
        console.log("\nRunning deploy:registry ...");
        await hyperdriveDeploy.ensureDeployed(
            name,
            "HyperdriveRegistry",
            [name],
            {
                ...rest,
            },
        );
    },
);
