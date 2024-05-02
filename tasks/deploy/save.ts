import { subtask, types } from "hardhat/config";
import { Deployments } from "./deployments";

export type DeploySaveParams = {
  name: string;
  abi: any;
  args: any[];
  contract: string;
  address: string;
  overwrite?: boolean;
};

subtask(
  "deploy:save",
  "Saves the contract to the deployments file and the hardhat-deploy artifacts then verifies it",
)
  .addParam(
    "name",
    "name of deployment artifact to verify (if left blank all are verified)",
    undefined,
    types.string,
  )
  .addParam("abi", "abi of the deployed contract", undefined, types.any)
  .addParam(
    "args",
    "constructor args passed to the deployed contract",
    undefined,
    types.any,
  )
  .addParam(
    "contract",
    "source contract the deployed contract is an instance of",
    undefined,
    types.string,
  )
  .addParam("address", "address for the deployed contract")
  .addOptionalParam(
    "overwrite",
    "overwrite an existing value for the contract in the deployments file",
    undefined,
    types.boolean,
  )
  .setAction(
    async (
      { name, abi, args, contract, address }: DeploySaveParams,
      { run, deployments: hhDeployments, network },
    ) => {
      await hhDeployments.save(name, { abi, args, address });
      Deployments.get().add(name, contract, address, network.name);
      // skip verification on non-live networks (hardhat,foundry,etc)
      if (network.live)
        await run("verify:verify", {
          address,
          constructorArguments: args,
          network: network.name,
        });
    },
  );
