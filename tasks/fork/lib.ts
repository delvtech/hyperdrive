/**
 * Used to get latest checkpoint id.
 */
export function getCheckpointId(
    checkpointDuration: bigint,
    blockTimestamp: bigint,
) {
    return blockTimestamp - (blockTimestamp % checkpointDuration);
}

/**
 * Used to control polling for long-running operations.
 */
export function sleep(minutes: number) {
    return new Promise((resolve) => setTimeout(resolve, minutes * 60 * 1000));
}
