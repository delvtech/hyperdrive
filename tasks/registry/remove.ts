import { task, types } from "hardhat/config";
import { Address, zeroAddress } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "../deploy";

export type RegistryRemoveParams = HyperdriveDeployBaseTaskParams & {
    address: string;
};

HyperdriveDeployBaseTask(
    task(
        "registry:remove",
        "remove the specified hyperdrive instance from the registry",
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
            console.log(`removing ${address} from registry ...`);
            const registryAddress = deployments.byName(
                network.name === "sepolia"
                    ? "SEPOLIA_REGISTRY"
                    : "DELV Hyperdrive Registry",
            ).address as `0x${string}`;
            const registryContract = await viem.getContractAt(
                "IHyperdriveGovernedRegistry",
                registryAddress,
            );
            let tx = await registryContract.write.setInstanceInfo([
                [address as Address],
                [0n],
                [zeroAddress],
            ]);
            let pc = await viem.getPublicClient();
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    );
