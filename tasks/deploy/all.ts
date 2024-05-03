import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { task, types } from "hardhat/config";
import { DeployCoordinatorsAllParams } from "./coordinators";
import { DeployFactoryParams } from "./factory";
import { DeployForwarderParams } from "./forwarder";
import { DeployInstancesAllParams } from "./instances";
import { DeployRegistryParams } from "./registry";
dayjs.extend(duration);

export type DeployAllParams = {
    overwrite?: boolean;
} & DeployCoordinatorsAllParams;

task(
    "deploy:all",
    "deploys the HyperdriveFactory, all deployer coordinators, and all hyperdrive instances",
)
    .addOptionalParam(
        "overwrite",
        "overwrite deployment artifacts if they exist",
        false,
        types.boolean,
    )
    .addOptionalParam(
        "lido",
        "address of the lido contract",
        undefined,
        types.string,
    )
    .addOptionalParam(
        "reth",
        "address of the reth contract",
        undefined,
        types.string,
    )
    .addOptionalParam("admin", "admin address", undefined, types.string)
    .setAction(async ({ admin, overwrite }: DeployAllParams, { run }) => {
        // deploy the forwarder
        await run("deploy:forwarder", { overwrite } as DeployForwarderParams);

        // deploy the factory
        await run("deploy:factory", { overwrite } as DeployFactoryParams);

        // deploy the registry
        await run("deploy:registry", { overwrite } as DeployRegistryParams);

        // deploy all deployer coordinators
        await run("deploy:coordinators:all", {
            admin,
            overwrite,
        } as DeployCoordinatorsAllParams);

        // deploy all instances
        await run("deploy:instances:all", {
            admin,
            overwrite,
        } as DeployInstancesAllParams);
    });
