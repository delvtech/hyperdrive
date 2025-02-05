import { task, types } from "hardhat/config";
import { Address, parseEther } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "../deploy";

export type UpdateGovernanceParams = HyperdriveDeployBaseTaskParams & {
    governance: Address;
};

HyperdriveDeployBaseTask(
    task("factory:update-governance", "updates governance on the factory"),
)
    .addParam("governance", "new governance address", undefined, types.string)
    .setAction(
        async (
            { governance }: Required<UpdateGovernanceParams>,
            { viem, hyperdriveDeploy: { deployments } },
        ) => {
            // Get the factory contract.
            let factoryAddress = deployments.byName(
                "ElementDAO Hyperdrive Factory",
            ).address as Address;
            const factoryContract = await viem.getContractAt(
                "IHyperdriveFactory",
                factoryAddress,
            );

            // Update the max time stretch to 20%.
            console.log(
                `current max time stretch ${await factoryContract.read.maxTimeStretchAPR()} ...`,
            );
            let pc = await viem.getPublicClient();
            let tx = await factoryContract.write.updateMaxTimeStretchAPR([
                parseEther("0.2"),
            ]);
            await pc.waitForTransactionReceipt({ hash: tx });
            console.log(
                `new max time stretch ${await factoryContract.read.maxTimeStretchAPR()} ...`,
            );

            // Update the max fixed rate to 50%.
            console.log(
                `current max fixed rate ${await factoryContract.read.maxFixedAPR()} ...`,
            );
            tx = await factoryContract.write.updateMaxFixedAPR([
                parseEther("0.5"),
            ]);
            await pc.waitForTransactionReceipt({ hash: tx });
            console.log(
                `new max fixed rate ${await factoryContract.read.maxFixedAPR()} ...`,
            );

            // Update the governance to the new address.
            console.log(
                `current governance address ${await factoryContract.read.governance()} ...`,
            );
            tx = await factoryContract.write.updateGovernance([governance]);
            await pc.waitForTransactionReceipt({ hash: tx });
            console.log(
                `new governance address ${await factoryContract.read.governance()} ...`,
            );
        },
    );
