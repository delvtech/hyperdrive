import { task } from "hardhat/config";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "./environment-extensions";

export type DeployRegistryParams = HyperdriveDeployBaseTaskParams & {
    name: string;
};

HyperdriveDeployBaseTask(
    task(
        "deploy:registry",
        "deploys the hyperdrive factory to the configured chain",
    ),
).setAction(
    async ({ name, ...rest }: DeployRegistryParams, { hyperdriveDeploy }) => {
        console.log("\nRunning deploy:registry ...");
        await hyperdriveDeploy.deployContract(name, "HyperdriveRegistry", [], {
            ...rest,
        });
    },
);
