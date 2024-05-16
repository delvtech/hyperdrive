import { subtask } from "hardhat/config";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "./lib";

export type DeployRegistryParams = HyperdriveDeployBaseTaskParams & {
    name: string;
};

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
