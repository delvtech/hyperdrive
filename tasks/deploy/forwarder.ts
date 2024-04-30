import { task, types } from "hardhat/config";

export type DeployForwarderParams = {
  overwrite?: boolean;
};

task(
  "deploy:forwarder",
  "deploys the ERC20ForwarderFactory to the configured chain",
)
  .addOptionalParam(
    "overwrite",
    "overwrite deployment artifacts if they exist",
    false,
    types.boolean,
  )
  .setAction(
    async (
      { overwrite }: DeployForwarderParams,
      { deployments, run, network, viem },
    ) => {
      const contractName = "ERC20ForwarderFactory";
      // Skip if deployed and overwrite=false.
      let artifacts = await deployments.all();
      if (!overwrite && artifacts[contractName]) {
        console.log(`${contractName} already deployed`);
        return;
      }
      // Deploy the ERC20ForwarderFactory
      console.log(`deploying ${contractName}...`);
      const linkerFactory = await viem.deployContract(contractName, []);
      await deployments.save(contractName, { ...linkerFactory, args: [] });
      await run("deploy:verify", { name: contractName });
    },
  );
