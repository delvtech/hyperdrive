import { subtask } from "hardhat/config";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "./lib";

export type DeployInstanceParams = HyperdriveDeployBaseTaskParams & {};

HyperdriveDeployBaseTask(
    subtask(
        "deploy:instance",
        "deploys the Hyperdrive instance with the provided name and chain",
    ),
).setAction(
    async ({ name, ...rest }: DeployInstanceParams, { hyperdriveDeploy }) => {
        console.log("\nRunning deploy:instance ...");
        await hyperdriveDeploy.deployInstance(name, rest);
    },
);
