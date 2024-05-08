import { task } from "hardhat/config";
import { DeployFactoryParams } from "./factory";

import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "./lib";
export type DeployAllParams = HyperdriveDeployBaseTaskParams & {};

HyperdriveDeployBaseTask(
    task(
        "deploy:all",
        "deploys the HyperdriveFactory, all deployer coordinators, and all hyperdrive instances",
    ),
).setAction(
    async ({ name, ...rest }: DeployAllParams, { run, config, network }) => {
        // deploy the registry
        await run("deploy:registry", {
            name: `${name}_REGISTRY`,
            ...rest,
        });

        let hyperdriveDeploy = config.networks[network.name].hyperdriveDeploy;
        if (!hyperdriveDeploy) {
            console.log("no config found for network");
            return;
        }

        for (let f of hyperdriveDeploy.factories ?? []) {
            await run("deploy:factory", {
                name: f.name,
                ...rest,
            } as DeployFactoryParams);
        }

        for (let f of hyperdriveDeploy.coordinators ?? []) {
            await run("deploy:coordinator", {
                name: f.name,
                ...rest,
            } as DeployFactoryParams);
        }

        for (let f of hyperdriveDeploy.instances ?? []) {
            await run("deploy:instance", {
                name: f.name,
                ...rest,
            } as DeployFactoryParams);
        }
    },
);
