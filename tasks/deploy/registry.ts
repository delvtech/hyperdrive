import { task } from "hardhat/config";

export type DeployRegistryParams = {};

task(
  "deploy:registry",
  "deploys the hyperdrive registry to the configured chain",
).setAction(
  async ({}: DeployRegistryParams, { deployments, run, network, viem }) => {
    console.log("deploying HyperdriveRegistry...");
    const name = `registry-${network.name}`;
    const hyperdriveRegistry = await viem.deployContract("HyperdriveRegistry", [
      name,
    ]);
    await deployments.save("HyperdriveRegistry", hyperdriveRegistry);
    if (network.name != "hardhat")
      await run("verify:verify", {
        address: hyperdriveRegistry.address,
        constructorArguments: [name],
        network: network.name,
      });
  },
);
