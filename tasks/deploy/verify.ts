import { task, types } from "hardhat/config";
import { zeroAddress } from "viem";

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
    async ({ name }: { name: string }, { deployments, run, network }) => {
      const artifact = await deployments.get(name);
      // Skip verifying contracts on test chains.
      if (!network.live) {
        console.log(`skipping verification on non-live network for ${name}`);
        return;
      }
      // Verify a single deployment if name is specified.
      if (name) {
        try {
          await run("verify:verify", {
            address: artifact.address,
            constructorArguments: artifact.args,
            network: network.name,
          });
        } catch (e) {
          console.error(e);
        }
        return;
      }
      // Verify all deployments for the network since name is unspecified.
      const deps = await deployments.all();
      for (let [_, { address, args }] of Object.entries(deps)) {
        try {
          await run("verify:verify", {
            address: address,
            constructorArguments: args,
            network: network.name,
          });
        } catch (e) {
          console.error(e);
        }
      }
    },
  );
