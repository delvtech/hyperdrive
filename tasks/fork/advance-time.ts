import { task, types } from "hardhat/config";
import {
    DurationString,
    HyperdriveDeployBaseTask,
    HyperdriveDeployBaseTaskParams,
    parseDuration,
} from "../deploy";

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
            for (
                let i = 0;
                (i + 1) * Number(checkpointSeconds) < timeSeconds;
                i++
            ) {
                console.log("hello");
                let pc = await viem.getPublicClient();
                let bn = await pc.getBlockNumber();
                let b = await pc.getBlock({
                    blockNumber: bn,
                });
                await tc.increaseTime({
                    seconds: Number(
                        checkpointSeconds + (b.timestamp % checkpointSeconds),
                    ),
                });

                bn = await pc.getBlockNumber();
                b = await pc.getBlock({
                    blockNumber: bn,
                });
                for (let instance of poolContracts) {
                    await instance.write.checkpoint([
                        checkpointSeconds + (b.timestamp % checkpointSeconds),
                        0n,
                    ]);
                }
            }
        },
    );
