import { task } from "hardhat/config";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "./environment-extensions";

export type DeployInstanceParams = HyperdriveDeployBaseTaskParams & {};

HyperdriveDeployBaseTask(
    task(
        "deploy:instance",
        "deploys the Hyperdrive instance with the provided name and chain",
    ),
).setAction(
    async ({ name, ...rest }: DeployInstanceParams, { hyperdriveDeploy }) => {
        console.log("\nRunning deploy:instance ...");
        await hyperdriveDeploy.deployInstance(name, rest);
    },
);
