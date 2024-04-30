import { task } from "hardhat/config";

export type DeployRegistryParams = {};

task(
  "deploy:registry",
  "deploys the hyperdrive registry to the configured chain",
).setAction(
  async ({}: DeployRegistryParams, { deployments, run, network, viem }) => {
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
