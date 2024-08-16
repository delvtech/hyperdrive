import { task } from "hardhat/config";
import { Address } from "viem";
import {
    HyperdriveDeployNamedTask,
    HyperdriveDeployNamedTaskParams,
} from "../deploy";

HyperdriveDeployNamedTask(
    task(
        "factory:remove-coordinator",
        "removes the specified deployer coordinator from the factory",
    ),
).setAction(
    async (
        { name }: Required<HyperdriveDeployNamedTaskParams>,
        { viem, hyperdriveDeploy: { deployments }, network },
    ) => {
        // Get the factory contract.
        let deployment = deployments.byName(name);
        console.log(
            `removing ${name} ${deployment.contract} at ${deployment.address} from the factory ...`,
        );
        let factoryAddress = deployments.byName("ElementDAO Hyperdrive Factory")
            .address as Address;
        const factoryContract = await viem.getContractAt(
            "IHyperdriveFactory",
            factoryAddress,
        );

        // Find the index of the deployer coordinator to remove.
        const coordinators =
            await factoryContract.read.getDeployerCoordinatorsInRange([
                0n,
                await factoryContract.read.getNumberOfDeployerCoordinators(),
            ]);
        const index = coordinators.findIndex(
            (c) => c.toLowerCase() === deployment.address.toLowerCase(),
        );

        // Remove the deployer coordinator.
        let tx = await factoryContract.write.removeDeployerCoordinator([
            deployment.address as Address,
            BigInt(index),
        ]);
        let pc = await viem.getPublicClient();
        await pc.waitForTransactionReceipt({ hash: tx });
    },
);
