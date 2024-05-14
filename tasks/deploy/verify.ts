import { task, types } from "hardhat/config";

export type VerifyParams = { name?: string };

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
    .setAction(
        async (
            { name: nameParam }: VerifyParams,
            { config, hyperdriveDeploy, deployments, network, run },
        ) => {
            for (let {
                name,
                address,
                contract,
                timestamp,
            } of hyperdriveDeploy.deployments
                .byNetwork(network.name)
                .filter((d) => !nameParam || d.name === nameParam)) {
                console.log(`verifying ${name} ${contract}...`);
                try {
                    await run("verify:verify", {
                        address,
                        constructorArguments: (await deployments.get(name))
                            .args,
                        libraries: {
                            ...((await deployments.get(name)).libraries ?? {}),
                        },
                    });
                } catch (e) {
                    console.error(e);
                }
            }
        },
    );
