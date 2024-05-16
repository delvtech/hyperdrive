import { subtask } from "hardhat/config";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "./lib";

export type DeployFactoryParams = HyperdriveDeployBaseTaskParams & {};

HyperdriveDeployBaseTask(
    subtask(
        "deploy:factory",
        "deploys the HyperdriveFactory with the provided name and chain",
    ),
).setAction(
    async ({ name, ...rest }: DeployFactoryParams, { hyperdriveDeploy }) => {
        console.log(`\nRunning deploy:factory ${name} ...`);
        await hyperdriveDeploy.deployFactory(name, rest);
    },
);
