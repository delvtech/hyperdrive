import { task, types } from "hardhat/config";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "../deploy";

export type DeployFactoryParams = HyperdriveDeployBaseTaskParams & {
    value: number;
};

HyperdriveDeployBaseTask(
    task(
        "registry:add",
        "adds the specified hyperdrive instance to the registry",
    ),
)
    .addParam(
        "value",
        "value to set for the instance in the registry",
        undefined,
        types.int,
    )
    .setAction(
        async (
            { name, value, ...rest }: Required<DeployFactoryParams>,
            { viem, hyperdriveDeploy: { deployments }, network },
        ) => {
            let deployment = deployments.byName(name);
            if (!deployment.contract.endsWith("Hyperdrive"))
                throw new Error("not a hyperdrive instance");
            console.log(
                `adding ${name} ${deployment.contract} at ${deployment.address} to registry with value ${value} ...`,
            );
            const registryAddress = deployments.byName(
                network.name.toUpperCase() + "_REGISTRY",
            ).address as `0x${string}`;
            const registryContract = await viem.getContractAt(
                "IHyperdriveGovernedRegistry",
                registryAddress,
            );
            let tx = await registryContract.write.setHyperdriveInfo([
                deployment.address as `0x${string}`,
                BigInt(value),
            ]);
            let pc = await viem.getPublicClient();
            await pc.waitForTransactionReceipt({ hash: tx });
        },
    );
