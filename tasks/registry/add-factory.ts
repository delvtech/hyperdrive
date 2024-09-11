import { task, types } from "hardhat/config";
import { Address } from "viem";
import {
    HyperdriveDeployNamedTask,
    HyperdriveDeployNamedTaskParams,
} from "../deploy";

export type AddRegistryParams = HyperdriveDeployNamedTaskParams & {
    value: number;
};

HyperdriveDeployNamedTask(
    task(
        "registry:add-factory",
        "adds the specified hyperdrive factory to the registry",
    ),
)
    .addParam(
        "value",
        "value to set for the factory in the registry",
        undefined,
        types.int,
    )
    .setAction(
        async (
            { name, value }: Required<AddRegistryParams>,
            { viem, hyperdriveDeploy: { deployments } },
        ) => {
            let deployment = deployments.byName(name);
            if (!deployment.contract.endsWith("Factory"))
                throw new Error("not a hyperdrive factory");
            const registryAddress = deployments.byName(
                "DELV Hyperdrive Registry",
            ).address as `0x${string}`;
            const registryContract = await viem.getContractAt(
                "HyperdriveRegistry",
                registryAddress,
            );
            let factoryCount =
                await registryContract.read.getNumberOfFactories();
            console.log(`there are ${factoryCount} factories in the registry`);
            console.log(
                `adding ${name} ${deployment.contract} at ${deployment.address} to registry with value ${value} ...`,
            );
            let tx = await registryContract.write.setFactoryInfo([
                [deployment.address as Address],
                [BigInt(value)],
            ]);
            let pc = await viem.getPublicClient();
            await pc.waitForTransactionReceipt({ hash: tx });
            factoryCount = await registryContract.read.getNumberOfFactories();
            console.log(
                `there are now ${factoryCount} factories in the registry`,
            );
        },
    );
