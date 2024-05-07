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
            {
                deployments: hhDeployments,
                hyperdriveDeploy: { deployments },
                run,
                network,
                artifacts,
            },
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
                const deploymentArtifact = deployments.byName(name);
                const artifact = await artifacts.readArtifact(
                    deploymentArtifact.contract,
                );
                try {
                    let { args } = await hhDeployments.get(name)!;
                    await run("verify:verify", {
                        address: deploymentArtifact.address,
                        constructorArguments: args,
                        contract:
                            artifact.sourceName + ":" + artifact.contractName,
                    });
                } catch (e) {
                    console.error(e);
                }
                return;
            }

            // Verify all deployed contracts for the network since name is unspecified.
            // - Use the deployments file to obtain the names of all deployed contracts.
            // - Use the hh-deploy artifacts to obtain the constructorArguments.
            const deployedContracts = deployments.byNetwork(network.name);
            for (let dc of deployedContracts) {
                let { args } = await hhDeployments.get(dc.name);
                await run("verify:verify", {
                    address: dc.address,
                    constructorArguments: args,
                    network: network.name,
                });
            }
        },
    );
