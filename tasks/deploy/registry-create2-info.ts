import { task } from "hardhat/config";
import { encodeAbiParameters, encodePacked, keccak256 } from "viem";
import {
    HyperdriveDeployNamedTask,
    HyperdriveDeployNamedTaskParams,
} from "./lib";

export type RegistryCreate2InfoParams = HyperdriveDeployNamedTaskParams;

HyperdriveDeployNamedTask(
    task(
        "registry-create2-info",
        "prints the bytecode hash of a HyperdriveRegistry with the provided name",
    ),
).setAction(async ({ name }: RegistryCreate2InfoParams, { artifacts }) => {
    // Assemble the creation code by packing the registry contract's
    // bytecode with its constructor arguments.
    let artifact = artifacts.readArtifactSync("HyperdriveRegistry");
    let creationCode = encodePacked(
        ["bytes", "bytes"],
        [
            artifact.bytecode,
            encodeAbiParameters([{ name: "_name", type: "string" }], [name]),
        ],
    );
    let hash = keccak256(creationCode);
    console.log(`HASH: ${hash}`);
});
