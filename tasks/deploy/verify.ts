import { task, types } from "hardhat/config";
import { evaluateValueOrHREFn } from "./lib";

export type VerifyParams = {};

task(
    "deploy:verify",
    "attempts to verify all deployed contracts for the specified network",
)
    .addOptionalParam(
        "name",
        "name of the contract to verify (leave blank to verify all deployed contracts)",
        undefined,
        types.string,
    )
    .setAction(async ({}: VerifyParams, hre) => {
        let { run, hyperdriveDeploy, config, network } = hre;
        let hyperdriveConfig = config.networks[network.name].hyperdriveDeploy;
        if (!hyperdriveConfig) {
            console.log("no config found for network");
            return;
        }

        for (let f of hyperdriveConfig.factories ?? []) {
            // resolve the constructor args
            let constructorArguments = await evaluateValueOrHREFn(
                f.constructorArguments,
                hre,
            );
            // verify the linker factory
            await run("verify:verify", {
                address: constructorArguments[0].linkerFactory,
                constructorArguments: [],
            });
            // verify the factory
            await run("verify:verify", {
                address: hyperdriveDeploy.deployments.byName(f.name).address,
                constructorArguments,
            });
        }

        // for (let f of hyperdriveConfig.coordinators ?? []) {
        //     await run("deploy:coordinator", {
        //         name: f.name,
        //         ...rest,
        //     } as DeployFactoryParams);
        // }
        //
        // for (let f of hyperdriveConfig.instances ?? []) {
        //     await run("deploy:instance", {
        //         name: f.name,
        //         ...rest,
        //     } as DeployFactoryParams);
        // }
    });
