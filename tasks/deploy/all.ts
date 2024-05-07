import { task } from "hardhat/config";
import { DeployFactoryParams } from "./factory";

import { DeployCoordinatorParams } from "./coordinator";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "./environment-extensions";
import { DeployInstanceParams } from "./instance";
export type DeployAllParams = HyperdriveDeployBaseTaskParams & {};

HyperdriveDeployBaseTask(
    task(
        "deploy:all",
        "deploys the HyperdriveFactory, all deployer coordinators, and all hyperdrive instances",
    ),
).setAction(async ({ name, ...rest }: DeployAllParams, { run }) => {
    // deploy the factory
    await run("deploy:factory", {
        name: "SAMPLE_FACTORY",
        ...rest,
    } as DeployFactoryParams);

    // deploy the coordinator
    await run("deploy:coordinator", {
        name: "SAMPLE_COORDINATOR",
        ...rest,
    } as DeployCoordinatorParams);

    // deploy the instance
    await run("deploy:instance", {
        name: "SAMPLE_INSTANCE",
        ...rest,
    } as DeployInstanceParams);
});
