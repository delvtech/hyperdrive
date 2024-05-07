import { task } from "hardhat/config";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "./lib";

export type DeployCoordinatorParams = HyperdriveDeployBaseTaskParams & {};

HyperdriveDeployBaseTask(
    task(
        "deploy:coordinator",
        "deploys the HyperdriveDeployerCoordinator with the provided name and chain",
    ),
).setAction(
    async (
        { name, ...rest }: DeployCoordinatorParams,
        { hyperdriveDeploy },
    ) => {
        console.log("\nRunning deploy:coordinator ...");
        await hyperdriveDeploy.deployCoordinator(name, rest);
    },
);
