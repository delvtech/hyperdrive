import { task } from "hardhat/config";
import { DeployCheckpointRewarderParams } from "./checkpoint-rewarder";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployNamedTaskParams,
} from "./lib";

export type DeployCheckpointSubrewarderParams = HyperdriveDeployNamedTaskParams;

HyperdriveDeployBaseTask(
    task(
        "deploy:checkpoint-subrewarder",
        "deploys the hyperdrive checkpoint subrewarder to the configured chain",
    ),
).setAction(
    async (
        { name, ...rest }: DeployCheckpointRewarderParams,
        { hyperdriveDeploy },
    ) => {
        console.log("\nRunning deploy:checkpoint-subrewarder ...");
        await hyperdriveDeploy.deployCheckpointSubrewarder(name, rest);
    },
);
