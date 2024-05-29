import { task, types } from "hardhat/config";
import { Address } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
} from "../deploy";

export type CreateCheckpointsParams = HyperdriveDeployBaseTaskParams & {
    pollInterval: number;
};

export function getCheckpointId(
    checkpointDuration: bigint,
    blockTimestamp: bigint,
) {
    return blockTimestamp - (blockTimestamp % checkpointDuration);
}

/**
 * Used to control polling for checkpoint creation.
 */
function sleep(minutes: number) {
    return new Promise((resolve) => setTimeout(resolve, minutes * 60 * 1000));
}

HyperdriveDeployBaseTask(
    task(
        "fork:create-checkpoints",
        "Long-running process that creates checkpoints for all hyperdrive instances when necessary",
    ),
)
    .addOptionalParam(
        "pollInterval",
        "Amount of time in minutes between polls for checkpoint state",
        1,
        types.int,
    )
    .setAction(
        async (
            { pollInterval }: Required<CreateCheckpointsParams>,
            { viem, artifacts, hyperdriveDeploy, config, network },
        ) => {
            let poolAddresses = config.networks[
                network.name
            ].hyperdriveDeploy!.instances.map(
                (instance) =>
                    hyperdriveDeploy.deployments.byName(instance.name).address,
            );
            console.log(`found ${poolAddresses!.length} pools`);
            let checkpointDurations = !poolAddresses
                ? []
                : await Promise.all(
                      poolAddresses.map(
                          async (a) =>
                              (
                                  await (
                                      await viem.getContractAt(
                                          "HyperdriveTarget0",
                                          a,
                                      )
                                  ).read.getPoolConfig()
                              ).checkpointDuration,
                      ),
                  );
            let pc = await viem.getPublicClient();
            while (true) {
                console.log(`Polling checkpoint status for all pools...`);
                for (let i = 0; i < poolAddresses!.length; i++) {
                    console.log(` - ${poolAddresses![i]}: `);
                    let bn = await pc.getBlockNumber();
                    let b = await pc.getBlock({
                        blockNumber: bn,
                    });
                    // Calculate what the lateset checkpoint timestamp should be for the instance and check whether the checkpoint exists.
                    // If the checkpoint does not exist, create it.
                    let latestCheckpointTimestamp = getCheckpointId(
                        checkpointDurations[i],
                        b.timestamp,
                    );
                    try {
                        console.log(
                            ` - ${poolAddresses![i]}: retrieving checkpoint status ${latestCheckpointTimestamp}...`,
                        );
                        // this will throw if the checkpoint doesn't exist
                        let hello = await (
                            await viem.getContractAt(
                                "IHyperdriveRead",
                                poolAddresses![i] as Address,
                            )
                        ).read.getCheckpoint([latestCheckpointTimestamp]);
                        console.log(
                            ` - ${poolAddresses![i]}: checkpoint exists`,
                        );
                    } catch (e) {
                        console.log(
                            ` - ${poolAddresses![i]}: creating checkpoint...`,
                        );
                        await (
                            await viem.getContractAt(
                                "HyperdriveTarget3",
                                poolAddresses![i],
                            )
                        ).write.checkpoint([latestCheckpointTimestamp, 0n]);
                        console.log(
                            ` - ${poolAddresses![i]}: checkpoint created`,
                        );
                    }
                }
                console.log(
                    `Finished updating checkpoints for all pools... sleeping for ${pollInterval} minutes`,
                );
                await sleep(pollInterval);
            }
        },
    );
