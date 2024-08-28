import { subtask } from "hardhat/config";
import {
    Address,
    encodeAbiParameters,
    encodeFunctionData,
    encodePacked,
    keccak256,
    stringToHex,
} from "viem";
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
        { hyperdriveDeploy, artifacts, getNamedAccounts, viem },
    ) => {
        console.log("\nRunning deploy:registry ...");
        // Skip if the registry is already deployed.
        if (!!hyperdriveDeploy.deployments.byNameSafe(name)) {
            console.log(`skipping ${name}, found existing deployment`);
            return;
        }

        // Ensure the Create2 factory is deployed.
        let create2Deployer = await hyperdriveDeploy.ensureDeployed(
            "Hyperdrive Create2 Factory",
            "HyperdriveCreate2Factory",
            [],
        );

        // Take the `REGISTRY_SALT` string and convert it to bytes32
        // compatible formatting.
        let salt = stringToHex(process.env.REGISTRY_SALT! as `0x${string}`, {
            size: 32,
        });

        // Assemble the creation code by packing the registry contract's
        // bytecode with its constructor arguments.
        let deployer = (await getNamedAccounts())["deployer"] as Address;
        let artifact = artifacts.readArtifactSync("HyperdriveRegistry");
        let creationCode = encodePacked(
            ["bytes", "bytes"],
            [
                artifact.bytecode,
                encodeAbiParameters(
                    [{ name: "_name", type: "string" }],
                    [name],
                ),
            ],
        );
        let initializationData = encodeFunctionData({
            abi: artifact.abi,
            functionName: "updateAdmin",
            args: [deployer],
        });

        // Retrieve the contract's bytecode from the artifact and pack it
        // with the constructor arguments to form the creation code.
        console.log(artifact.bytecode);
        let tx = await create2Deployer.write.deploy([
            salt,
            creationCode,
            initializationData,
        ]);
        let pc = await viem.getPublicClient();
        await pc.waitForTransactionReceipt({ hash: tx });
        console.log(` - saving ${name}...`);

        // Use the deployer address to back-compute the deployed contract address
        // and store the deployment configuration in deployments.json.
        let deployedAddress = await create2Deployer.read.getDeployed([
            salt,
            keccak256(creationCode),
        ]);
        hyperdriveDeploy.deployments.add(
            name,
            "HyperdriveRegistry",
            deployedAddress,
        );

        let registry = await viem.getContractAt(
            "HyperdriveRegistry",
            deployedAddress,
        );
        console.log(
            `NumFactories: ${await registry.read.getNumberOfInstances()}`,
        );
    },
);
