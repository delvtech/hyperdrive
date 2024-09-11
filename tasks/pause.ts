import { task, types } from "hardhat/config";
import {
    HyperdriveDeployNamedTask,
    HyperdriveDeployNamedTaskParams,
} from "./deploy";

export type PauseParams = HyperdriveDeployNamedTaskParams & {
    status: boolean;
};

HyperdriveDeployNamedTask(task("pause", "pauses the specified Hyperdrive pool"))
    .addParam("status", "the pause status to set", undefined, types.boolean)
    .setAction(
        async (
            { name, status }: Required<PauseParams>,
            { viem, hyperdriveDeploy: { deployments } },
        ) => {
            let deployment = deployments.byName(name);
            if (!deployment.contract.endsWith("Hyperdrive"))
                throw new Error("not a hyperdrive instance");
            let poolContract = await viem.getContractAt(
                "IHyperdrive",
                deployment.address,
            );
            console.log(
                `the pause status is ${(await poolContract.read.getMarketState()).isPaused}`,
            );
            console.log(
                `setting the pause status of ${name} ${deployment.contract} at ${deployment.address} to ${status} ...`,
            );
            let tx = await poolContract.write.pause([status]);
            let pc = await viem.getPublicClient();
            await pc.waitForTransactionReceipt({ hash: tx });
            console.log(
                `the pause status is now ${(await poolContract.read.getMarketState()).isPaused}`,
            );
        },
    );
