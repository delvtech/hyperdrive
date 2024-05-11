import { Hex, keccak256, toHex } from "viem";

// Gets a deployment ID to use in deployments that is resistant to collisions.
// This deployment ID accepts a prefix to namespace to the deployment ID and
// then hashes this with the current time.
export function getDeploymentId(prefix: string): Hex {
    return keccak256(toHex(`${prefix} - ${new Date().toUTCString()}`));
}
