import { task, types } from "hardhat/config";

export type DeployRegistryParams = { overwrite?: boolean };

task(
  "deploy:registry",
  "deploys the hyperdrive registry to the configured chain",
)
  .addOptionalParam(
    "overwrite",
    "overwrite deployment artifacts if they exist",
    false,
    types.boolean,
  )
  .setAction(
    async (
      { overwrite }: DeployRegistryParams,
      { deployments, run, network, viem },
    ) => {
      // Skip if deployed and overwrite=false.
      let artifacts = await deployments.all();
      if (!overwrite && artifacts["HyperdriveRegistry"]) {
        console.log(`"HyperdriveRegistry" already deployed`);
        return;
      }
      console.log("deploying HyperdriveRegistry...");
      let hyperdriveRegistry = await viem.deployContract("HyperdriveRegistry", [
        `registry-${network.name}`,
      ]);
      await deployments.save("HyperdriveRegistry", {
        ...hyperdriveRegistry,
        args: [`registry-${network.name}`],
      });
      await run("deploy:verify", { name: "HyperdriveRegistry" });
    },
  );
