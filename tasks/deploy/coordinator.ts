import { subtask } from "hardhat/config";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployNamedTaskParams,
} from "./lib";

export type DeployCoordinatorParams = HyperdriveDeployNamedTaskParams & {};

HyperdriveDeployBaseTask(
    subtask(
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
