import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployNamedTaskParams,
} from "./lib";

export type DeployCheckpointRewarderParams = HyperdriveDeployNamedTaskParams;

HyperdriveDeployBaseTask(
    subtask(
        "deploy:checkpoint-rewarder",
        "deploys the hyperdrive checkpoint rewarder to the configured chain",
    ),
).setAction(
    async (
        { name, ...rest }: DeployCheckpointRewarderParams,
        { hyperdriveDeploy },
    ) => {
        console.log("\nRunning deploy:checkpoint-rewarder ...");
        await hyperdriveDeploy.deployCheckpointRewarder(name, rest);
    },
);
