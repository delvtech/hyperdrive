import { task } from "hardhat/config";
import { DeployFactoryParams } from "./factory";

import { DeployCoordinatorParams } from "./coordinator";
import { DeployInstanceParams } from "./instance";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "./lib";
export type DeployHyperdriveParams = HyperdriveDeployBaseTaskParams & {};

HyperdriveDeployBaseTask(
    task(
        "deploy:hyperdrive",
        "deploys the HyperdriveFactory, all deployer coordinators, and all hyperdrive instances",
    ),
).setAction(
    async ({ ...rest }: DeployHyperdriveParams, { run, config, network }) => {
        // compile contracts
        await run("compile", { force: true, quiet: true });

        // deploy the registry
        await run("deploy:registry", {
            name: `${network.name.toUpperCase()}_REGISTRY`,
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

        for (let c of hyperdriveDeploy.coordinators ?? []) {
            await run("deploy:coordinator", {
                name: c.name,
                ...rest,
            } as DeployCoordinatorParams);
        }

        for (let i of hyperdriveDeploy.instances ?? []) {
            await run("deploy:instance", {
                name: i.name,
                ...rest,
            } as DeployInstanceParams);
        }
        if (network.name != "hardhat" && network.name != "localhost") {
            await run("deploy:verify");
        }
    },
);
