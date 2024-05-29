export function getCheckpointId(
    checkpointDuration: bigint,
    blockTimestamp: bigint,
) {
    return blockTimestamp - (blockTimestamp % checkpointDuration);
}
