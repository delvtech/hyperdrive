import { task } from "hardhat/config";

export type DeployForwarderParams = {};

task(
  "deploy:forwarder",
  "deploys the ERC20ForwarderFactory to the configured chain",
).setAction(
  async ({}: DeployForwarderParams, { deployments, run, network, viem }) => {
    // Deploy the ERC20ForwarderFactory
    console.log("deploying ERC20ForwarderFactory...");
    const linkerFactory = await viem.deployContract(
      "ERC20ForwarderFactory",
      [],
    );
    await deployments.save("ERC20ForwarderFactory", linkerFactory);
    if (network.name != "hardhat")
      await run("verify:verify", {
        address: linkerFactory.address,
        constructorArguments: [],
        network: network.name,
      });
  },
);
