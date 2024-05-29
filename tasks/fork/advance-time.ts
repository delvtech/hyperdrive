import { task, types } from "hardhat/config";
import {
    DurationString,
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
    parseDuration,
} from "../deploy";
import { getCheckpointId } from "./lib";

export type AdvanceTimeParams = HyperdriveDeployBaseTaskParams & {
    time: DurationString;
    checkpoint?: DurationString;
};

HyperdriveDeployBaseTask(
    task(
        "fork:advance-time",
        "Advances time for all hyperdrive instances creating checkpoints along the way if '--checkpoint' is provided a duration",
    ),
)
    .addParam(
        "time",
        "amount of time to advance by (string in the format of '<n> <minutes|hours|days|weeks|years>')",
        undefined,
        types.string,
    )
    .addOptionalParam(
        "checkpoint",
        "if defined, will checkpoint all pools on this interval over the time advancement (same format as time parameter)",
        undefined,
        types.string,
    )
    .setAction(
        async (
            { time, checkpoint }: Required<AdvanceTimeParams>,
            { viem, artifacts, hyperdriveDeploy, config, network },
        ) => {
            let tc = await viem.getTestClient({
                mode: "anvil",
            });
            let timeSeconds = parseDuration(time);
            // if checkpoint param is blank, simply advance time and return
            if (!checkpoint) {
                await tc.increaseTime({
                    seconds: Number(timeSeconds),
                });
                return;
            }

            let checkpointSeconds = parseDuration(checkpoint);
            let poolAddresses = config.networks[
                network.name
            ].hyperdriveDeploy?.instances.map(
                (instance) =>
                    hyperdriveDeploy.deployments.byName(instance.name).address,
            );
            let poolContracts = !poolAddresses
                ? []
                : await Promise.all(
                      poolAddresses.map(async (a) =>
                          viem.getContractAt("HyperdriveTarget3", a),
                      ),
                  );

            // Loop through time intervals of duration `checkpoint` until the total duration to advance time is reached.
            for (
                let i = 0;
                (i + 1) * Number(checkpointSeconds) < timeSeconds;
                i++
            ) {
                let pc = await viem.getPublicClient();
                let bn = await pc.getBlockNumber();
                let b = await pc.getBlock({
                    blockNumber: bn,
                });

                // Calculate what the lateset checkpoint timestamp should be for the instance.
                let latestCheckpointTimestamp = getCheckpointId(
                    checkpointSeconds,
                    b.timestamp,
                );
                // Loop through each pool and create checkpoints if necessary.
                for (let instance of poolContracts) {
                    try {
                        // this will throw if the checkpoint doesn't exist
                        await (
                            await viem.getContractAt(
                                "IHyperdriveRead",
                                instance.address,
                            )
                        ).read.getCheckpoint([latestCheckpointTimestamp]);
                        console.log("checkpoint exists");
                    } catch (e) {
                        console.log("writing checkpoint");
                        await instance.write.checkpoint([
                            latestCheckpointTimestamp,
                            0n,
                        ]);
                    }
                }

                console.log("advancing time");
                await tc.increaseTime({
                    seconds: Number(
                        checkpointSeconds + (b.timestamp % checkpointSeconds),
                    ),
                });
            }
        },
    );
