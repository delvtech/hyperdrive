import { task, types } from "hardhat/config";

export type RegistryAddParams = {
  address: string;
  value: string | number | bigint;
};

task("registry:add", "adds the specified hyperdrive instance to the registry")
  .addParam(
    "address",
    "address of the hyperdrive instance to add",
    undefined,
    types.string,
  )
  .addParam(
    "value",
    "value to be set in the registry for the instance",
    1,
    types.string,
  )
  .setAction(
    async (
      { address, value }: Required<RegistryAddParams>,
      { deployments, viem },
    ) => {
      console.log(
        `adding hyperdrive instance at ${address} to registry with value ${value}`,
      );
      const registryAddress = (await deployments.get("HyperdriveRegistry"))
        .address as `0x${string}`;
      const registryContract = await viem.getContractAt(
        "IHyperdriveGovernedRegistry",
        registryAddress,
      );
      await registryContract.write.setHyperdriveInfo([
        address as `0x${string}`,
        BigInt(value),
      ]);
    },
  );
