import { task, types } from "hardhat/config";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "../deploy";

export type RegistryUpdateGovernanceParams = HyperdriveDeployBaseTaskParams & {
    address: string;
};

HyperdriveDeployBaseTask(
    task(
        "registry:update-governance",
        "sets the registry governance address to the specified value",
    ),
)
    .addParam(
        "address",
        "address to set for governance in the registry",
        undefined,
        types.string,
    )
    .setAction(
        async (
            { address }: Required<RegistryUpdateGovernanceParams>,
            { viem, hyperdriveDeploy: { deployments }, network },
        ) => {
            const registryAddress = deployments.byName(
                "DELV Hyperdrive Registry",
            ).address as `0x${string}`;
            const registryContract = await viem.getContractAt(
                "IHyperdriveGovernedRegistry",
                registryAddress,
            );
            let tx = await registryContract.write.updateAdmin([
                address as `0x${string}`,
            ]);
            let pc = await viem.getPublicClient();
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    );
