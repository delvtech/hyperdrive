import { task, types } from "hardhat/config";
import { evaluateValueOrHREFn } from "./lib";

export type VerifyParams = {};

function sleep(ms: number) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

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

        // loop through all factories
        for (let f of hyperdriveConfig.factories ?? []) {
            // resolve the constructor args
            let constructorArguments = await evaluateValueOrHREFn(
                f.constructorArguments,
                hre,
            );

            // verify the linker factory
            console.log(`verifying ${f.name} linker factory...`);
            await run("verify:verify", {
                address: constructorArguments[0].linkerFactory,
                constructorArguments: [],
            });

            // verify the factory
            console.log(`verifying ${f.name}...`);
            await run("verify:verify", {
                address: hyperdriveDeploy.deployments.byName(f.name).address,
                constructorArguments,
            });
        }

        // loop through all instances
        for (let c of hyperdriveConfig.coordinators ?? []) {
            // verify the core deployer
            let coreDeployer = `${c.name}_${c.prefix}HyperdriveCoreDeployer`;
            let coreAddress =
                hyperdriveDeploy.deployments.byName(coreDeployer).address;
            console.log(
                `verifying ${c.name} ${c.prefix}HyperdriveCoreDeployer...`,
            );
            await run("verify:verify", {
                address: coreAddress,
                constructorArguments: c.extraConstructorArgs
                    ? await evaluateValueOrHREFn(
                          c.extraConstructorArgs,
                          hre,
                          {},
                      )
                    : [],
            });

            // verify the targets
            let targets = [];
            for (let i = 0; i < c.targetCount; i++) {
                await sleep(1000);
                let target = `${c.name}_${c.prefix}Target${i}Deployer`;
                let address =
                    hyperdriveDeploy.deployments.byName(target).address;
                targets.push(address);
                console.log(`verifying ${target}...`);
                await run("verify:verify", {
                    address,
                    constructorArguments: c.extraConstructorArgs
                        ? await evaluateValueOrHREFn(
                              c.extraConstructorArgs,
                              hre,
                              {},
                          )
                        : [],
                    libraries: {
                        LPMath: hyperdriveDeploy.deployments.byName("LPMath")
                            .address,
                    },
                });
            }

            // verify the coordinator
            console.log(`verifying ${c.name}...`);
            await run("verify:verify", {
                address: hyperdriveDeploy.deployments.byName(c.name).address,
                constructorArguments: [
                    await evaluateValueOrHREFn(c.factoryAddress, hre, {}),
                    coreAddress,
                    ...targets,
                    ...(c.token
                        ? [await evaluateValueOrHREFn(c.token, hre, {})]
                        : []),
                ],
            });
        }

        // loop through all instances
        for (let i of hyperdriveConfig.instances ?? []) {
            let instance = hre.hyperdriveDeploy.deployments.byName(i.name);
            let instanceContract = await hre.viem.getContractAt(
                "IHyperdriveRead",
                instance.address,
            );
            let poolConfig = await instanceContract.read.getPoolConfig();

            // verify the targets
            let targets = [];
            for (let j = 0; j < i.targetCount; j++) {
                await sleep(1000);
                let targetName = `${i.name}_${i.prefix}Target${j}`;
                let targetAddress =
                    hre.hyperdriveDeploy.deployments.byName(targetName).address;
                targets.push(targetAddress);
                console.log(`verifying ${targetName}...`);
                await run("verify:verify", {
                    address: targetAddress,
                    constructorArguments: [poolConfig],
                    libraries: {
                        LPMath: hyperdriveDeploy.deployments.byName("LPMath")
                            .address,
                    },
                });
            }

            // verify the instance
            console.log(`verifying ${i.name}...`);
            await run("verify:verify", {
                address: hre.hyperdriveDeploy.deployments.byName(i.name)
                    .address,
                constructorArguments: [poolConfig, ...targets],
                contract: `contracts/src/instances/${i.prefix.toLowerCase()}/${i.prefix}Hyperdrive.sol:${i.prefix}Hyperdrive`,
            });
        }
    });
