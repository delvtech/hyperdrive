import { task } from "hardhat/config";
import { DeployCheckpointRewarderParams } from "./checkpoint-rewarder";
import { DeployCheckpointSubrewarderParams } from "./checkpoint-subrewarder";
import { DeployCoordinatorParams } from "./coordinator";
import { DeployFactoryParams } from "./factory";
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
        // Only force compile contracts if network is live.
        console.log("compiling contracts");
        await run("compile", { force: network.live, quiet: true });

        // deploy the registry
        await run("deploy:registry", {
            // TODO: Generalize this.
            name: "DELV Hyperdrive Registry",
            ...rest,
        });

        let hyperdriveDeploy = config.networks[network.name].hyperdriveDeploy;
        if (!hyperdriveDeploy) {
            console.log("no config found for network");
            return;
        }

        for (let r of hyperdriveDeploy.checkpointRewarders ?? []) {
            await run("deploy:checkpoint-rewarder", {
                name: r.name,
                ...rest,
            } as DeployCheckpointRewarderParams);
        }

        for (let s of hyperdriveDeploy.checkpointSubrewarders ?? []) {
            await run("deploy:checkpoint-subrewarder", {
                name: s.name,
                ...rest,
            } as DeployCheckpointSubrewarderParams);
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
    },
);
