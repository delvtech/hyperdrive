import { subtask } from "hardhat/config";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployNamedTaskParams,
} from "./lib";

export type DeployInstanceParams = HyperdriveDeployNamedTaskParams & {};

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
