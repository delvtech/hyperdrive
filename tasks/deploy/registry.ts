import { subtask } from "hardhat/config";
import {
    Address,
    encodeAbiParameters,
    encodeFunctionData,
    encodePacked,
    stringToHex,
} from "viem";
import {
    CREATE_X_FACTORY,
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

        let deployer = (await getNamedAccounts())["deployer"] as Address;

        // Skip if the registry is already deployed.
        if (!!hyperdriveDeploy.deployments.byNameSafe(name)) {
            console.log(`skipping ${name}, found existing deployment`);
            return;
        }

        let createXDeployer = await viem.getContractAt(
            "IDeterministicDeployer",
            CREATE_X_FACTORY,
        );

        // Take the `REGISTRY_SALT` string and convert it to bytes32
        // compatible formatting.
        let salt = stringToHex(process.env.REGISTRY_SALT! as `0x${string}`, {
            size: 32,
        });

        // Assemble the creation code by packing the registry contract's
        // bytecode with its constructor arguments.
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

        // Call the Create2 deployer to deploy the contract.
        let tx = await createXDeployer.write.deployCreate2AndInit([
            salt,
            creationCode,
            initializationData,
            { constructorAmount: 0n, initCallAmount: 0n },
        ]);
        let pc = await viem.getPublicClient();
        let receipt = await pc.waitForTransactionReceipt({ hash: tx });
        let deployedAddress = receipt.logs[1].address;

        // Use the deployer address to back-compute the deployed contract address
        // and store the deployment configuration in deployments.json.
        console.log(` - saving ${name}...`);
        hyperdriveDeploy.deployments.add(
            name,
            "HyperdriveRegistry",
            deployedAddress as Address,
        );
    },
);
