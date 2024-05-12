import { task } from "hardhat/config";

export type VerifyParams = {};

task(
    "deploy:verify",
    "attempts to verify all deployed contracts for the specified network",
).setAction(
    async (
        {}: VerifyParams,
        { config, hyperdriveDeploy, deployments, network, run },
    ) => {
        for (let {
            name,
            address,
            contract,
            timestamp,
        } of hyperdriveDeploy.deployments.byNetwork(network.name)) {
            await run("verify:verify", {
                address,
                constructorArguments: (await deployments.get(name)).args,
                libraries: {
                    ...((await deployments.get(name)).libraries ?? {}),
                },
            });
        }
    },
);
