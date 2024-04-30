import { task } from "hardhat/config";

export type DeployForwarderParams = {};

task(
  "deploy:forwarder",
  "deploys the ERC20ForwarderFactory to the configured chain",
).setAction(
  async ({}: DeployForwarderParams, { deployments, run, network, viem }) => {
    // Deploy the ERC20ForwarderFactory
    const name = "ERC20ForwarderFactory";
    console.log(`deploying ${name}...`);
    const linkerFactory = await viem.deployContract(name, []);
    await deployments.save(name, { ...linkerFactory, args: [] });
    await run("deploy:verify", { name: "ERC20ForwarderFactory" });
  },
);
