import { task, types } from "hardhat/config";
import { Deployments } from "./deployments";

/**
 * Verify contracts using information from the deployment artifacts.
 * - Only runs on live networks (not hardhat)
 * - If no name is specified all contracts will be verified
 */
task(
  "deploy:verify",
  "verifies all contracts stored in the deployment artifacts",
)
  .addOptionalParam(
    "name",
    "name of deployment artifact to verify (if left blank all are verified)",
    undefined,
    types.string,
  )
  .setAction(
    async (
      { name }: { name: string },
      { deployments: hhDeployments, run, network },
    ) => {
      // Skip verifying contracts on test chains.
      if (!network.live) {
        console.log(`skipping verification on non-live network for ${name}`);
        return;
      }

      // Verify a single deployment if name is specified.
      if (name) {
        const artifact = await hhDeployments.get(name);
        if (name) {
          try {
            await run("verify:verify", {
              address: Deployments.get().byName(name, network.name)?.address,
              constructorArguments: artifact.args,
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
      const deployedContracts = Deployments.get().byNetwork(network.name);
      for (let dc of deployedContracts) {
        console.log("hello");
        // Skip verifying the contract if it isn't necessary

        // NOTE: It's possible that addresses differ between the artifacts and the file.
        // We should not handle this case because so long as they had the same
        // constructorArguments, the contract will verify.
        let { args } = await hhDeployments.get(dc.name);
        await run("verify:verify", {
          address: dc.address,
          constructorArguments: args,
          network: network.name,
        });
      }
    },
  );
