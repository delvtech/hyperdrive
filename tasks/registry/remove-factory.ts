import { task, types } from "hardhat/config";
import { Address } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "../deploy";

export type RegistryRemoveParams = HyperdriveDeployBaseTaskParams & {
    address: string;
};

HyperdriveDeployBaseTask(
    task(
        "registry:remove-factory",
        "remove the specified hyperdrive factory from the registry",
    ),
)
    .addParam(
        "address",
        "address of the instance to remove",
        undefined,
        types.string,
    )
    .setAction(
        async (
            { address }: Required<RegistryRemoveParams>,
            { viem, hyperdriveDeploy: { deployments }, network },
        ) => {
            const registryAddress = deployments.byName(
                network.name === "sepolia"
                    ? "SEPOLIA_REGISTRY"
                    : "DELV Hyperdrive Registry",
            ).address as `0x${string}`;
            const registryContract = await viem.getContractAt(
                "IHyperdriveGovernedRegistry",
                registryAddress,
            );
            let factoryCount =
                await registryContract.read.getNumberOfFactories();
            console.log(`there are ${factoryCount} factories in the registry`);
            console.log(`removing ${address} from registry ...`);
            let tx = await registryContract.write.setFactoryInfo([
                [address as Address],
                [0n],
            ]);
            let pc = await viem.getPublicClient();
            await pc.waitForTransactionReceipt({ hash: tx });
            factoryCount = await registryContract.read.getNumberOfFactories();
            console.log(
                `there are now ${factoryCount} factories in the registry`,
            );
        },
    );
