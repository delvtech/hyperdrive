import { subtask } from "hardhat/config";
import { Address, encodeAbiParameters, encodePacked, stringToHex } from "viem";
import {
    HyperdriveDeployBaseTask,
    HyperdriveDeployNamedTaskParams,
} from "./lib";

export type DeployRegistryParams = HyperdriveDeployNamedTaskParams;

HyperdriveDeployBaseTask(
    subtask(
        "deploy:registry",
        "deploys the hyperdrive registry to the configured chain",
    ),
).setAction(
    async (
        { name }: DeployRegistryParams,
        { hyperdriveDeploy, artifacts, getNamedAccounts },
    ) => {
        console.log("\nRunning deploy:registry ...");
        // Skip if the registry is already deployed.
        if (!!hyperdriveDeploy.deployments.byNameSafe(name)) {
            console.log(`skipping ${name}, found existing deployment`);
            return;
        }

        // Ensure the Create3 factory is deployed.
        let create3Deployer = await hyperdriveDeploy.ensureDeployed(
            "Hyperdrive Create3 Factory",
            "HyperdriveCreate3Factory",
            [],
        );

        // Retrieve the contract's bytecode from the artifact and pack it
        // with the constructor arguments to form the creation code.
        let artifact = artifacts.readArtifactSync("HyperdriveRegistry");
        let address = await create3Deployer.write.deploy([
            stringToHex(process.env.REGISTRY_SALT! as `0x${string}`, {
                size: 32,
            }),
            encodePacked(
                ["bytes", "bytes"],
                [
                    artifact.bytecode,
                    encodeAbiParameters(
                        [{ name: "_name", type: "string" }],
                        [name],
                    ),
                ],
            ),
        ]);
        console.log(` - saving ${name}... ${address}`);
        let deployer = (await getNamedAccounts())["deployer"];
        hyperdriveDeploy.deployments.add(
            name,
            "HyperdriveRegistry",
            await create3Deployer.read.getDeployed([
                deployer as Address,
                stringToHex(process.env.REGISTRY_SALT! as `0x${string}`, {
                    size: 32,
                }),
            ]),
        );
    },
);
