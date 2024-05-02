import { task, types } from "hardhat/config";
import { Deployments } from "./deployments";
import { DeploySaveParams } from "./save";

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
    async ({ overwrite }: DeployRegistryParams, { run, network, viem }) => {
      // Skip if deployed and overwrite=false.
      if (
        !overwrite &&
        Deployments.get().byNameSafe("HyperdriveRegistry", network.name)
      ) {
        console.log(`"HyperdriveRegistry" already deployed`);
        return;
      }
      console.log("deploying HyperdriveRegistry...");
      let hyperdriveRegistry = await viem.deployContract("HyperdriveRegistry", [
        `registry-${network.name}`,
      ]);
      await run("deploy:save", {
        name: "HyperdriveRegistry",
        args: [],
        abi: hyperdriveRegistry.abi,
        address: hyperdriveRegistry.address,
        contract: "HyperdriveRegistry",
      } as DeploySaveParams);
    },
  );
