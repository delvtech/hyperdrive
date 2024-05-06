import { task, types } from "hardhat/config";

/**
 * Verify contracts using information from the deployment artifacts.
 * - Only runs on live networks (not hardhat)
 * - If no name is specified all contracts will be verified
 */
task("deploy:verify", "verifies contract(s) from the deployments file")
    .addOptionalParam(
        "name",
        "name of deployment artifact to verify (if left blank all are verified)",
        undefined,
        types.string,
    )
    .setAction(
        async (
            { name }: { name: string },
            { hyperdriveDeploy: { deployments }, run, network },
        ) => {
            // Skip verifying contracts on test chains.
            if (!network.live) {
                console.log(
                    `skipping verification on non-live network for ${name}`,
                );
                return;
            }

            // Verify a single deployment if name is specified.
            if (name) {
                const artifact = deployments.byName(name, network.name);
                if (name) {
                    try {
                        let { args } = deployments.data(name, network.name);
                        await run("verify:verify", {
                            address: artifact.address,
                            constructorArguments: args,
                            network: network.name,
                        });
                    } catch (e) {
                        console.error(e);
                    }
                    return;
                }
            }

            // Verify all deployed contracts for the network since name is unspecified.
            // - Use the deployments file to obtain the names of all deployed contracts.
            // - Use the hh-deploy artifacts to obtain the constructorArguments.
            const deployedContracts = deployments.byNetwork(network.name);
            for (let dc of deployedContracts) {
                let { args } = deployments.data(dc.name, network.name);
                await run("verify:verify", {
                    address: dc.address,
                    constructorArguments: args,
                    network: network.name,
                });
            }
        },
    );
