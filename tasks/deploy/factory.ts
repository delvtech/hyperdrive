import { task } from "hardhat/config";
import {
    HyperdriveDeployBaseTaskParams,
    HyperdriveDeployBaseTask,
} from "./environment-extensions";

export type DeployFactoryParams = HyperdriveDeployBaseTaskParams & {};

HyperdriveDeployBaseTask(
    task(
        "deploy:factory",
        "deploys the HyperdriveFactory with the provided name and chain",
    ),
).setAction(async (params: DeployFactoryParams, { hyperdriveDeploy }) => {
    console.log("\nRunning deploy:factory ...");
    await hyperdriveDeploy.deployFactory("hello", params);
});
