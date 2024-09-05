import { subtask } from "hardhat/config";
import {
    Address,
    encodeAbiParameters,
    encodeFunctionData,
    encodePacked,
    isHex,
    parseEther,
    zeroAddress,
} from "viem";
import {
    CREATE_X_FACTORY,
    CREATE_X_FACTORY_DEPLOYER,
    CREATE_X_PRESIGNED_TRANSACTION,
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
        { hyperdriveDeploy, artifacts, getNamedAccounts, viem, network },
    ) => {
        console.log("\nRunning deploy:registry ...");

        let deployer = (await getNamedAccounts())["deployer"] as Address;

        if (network.name == "anvil") {
            let tc = await viem.getTestClient();
            await tc.setBalance({
                value: parseEther("1"),
                address: CREATE_X_FACTORY_DEPLOYER,
            });
            let wc = await viem.getWalletClient(CREATE_X_FACTORY_DEPLOYER);
            await wc.sendRawTransaction({
                serializedTransaction: CREATE_X_PRESIGNED_TRANSACTION,
            });
        }

        // Skip if the registry is already deployed.
        if (!!hyperdriveDeploy.deployments.byNameSafe(name)) {
            console.log(`skipping ${name}, found existing deployment`);
            return;
        }

        let createXDeployer = await viem.getContractAt(
            "IDeterministicDeployer",
            CREATE_X_FACTORY,
        );

        // Read the salt from the environment and ensure it is a hex string.
        let salt = process.env.REGISTRY_SALT! as `0x${string}`;
        if (!isHex(salt)) {
            console.error(
                'Invalid REGISTRY_SALT, must be a "0x" prefixed hex string',
            );
        }

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
            zeroAddress,
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
