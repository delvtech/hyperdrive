import { subtask } from "hardhat/config";
import {
    Address,
    decodeEventLog,
    encodeFunctionData,
    encodePacked,
} from "viem";
import { CREATEX_ABI } from "../../lib/createx/interface/src/lib/constants";
import {
    CREATE_X_FACTORY,
    HyperdriveDeployBaseTask,
    HyperdriveDeployNamedTaskParams,
    REGISTRY_SALT,
    deployCreateX,
} from "./lib";

export type DeployRegistryParams = HyperdriveDeployNamedTaskParams;

HyperdriveDeployBaseTask(
    subtask(
        "deploy:registry",
        "deploys the hyperdrive registry to the configured chain",
    ),
).setAction(async ({ name }: DeployRegistryParams, hre) => {
    console.log("\nRunning deploy:registry ...");
    const { hyperdriveDeploy, artifacts, getNamedAccounts, viem } = hre;

    let deployer = (await getNamedAccounts())["deployer"] as Address;

    // If the network is anvil, we need to deploy the CREATEX factory if it
    // hasn't been deployed before.
    await deployCreateX(hre);

    // Skip if the registry is already deployed.
    if (!!hyperdriveDeploy.deployments.byNameSafe(name)) {
        console.log(`skipping ${name}, found existing deployment`);
        return;
    }

    let createXDeployer = await viem.getContractAt(
        "IDeterministicDeployer",
        CREATE_X_FACTORY,
    );

    // Assemble the creation code by packing the registry contract's
    // bytecode with its constructor arguments.
    let artifact = artifacts.readArtifactSync("HyperdriveRegistry");
    let creationCode = encodePacked(["bytes"], [artifact.bytecode]);
    let initializationData = encodeFunctionData({
        abi: artifact.abi,
        functionName: "initialize",
        args: [name, deployer],
    });

    // Call the Create3 deployer to deploy the contract.
    let tx = await createXDeployer.write.deployCreate3AndInit([
        REGISTRY_SALT,
        creationCode,
        initializationData,
        { constructorAmount: 0n, initCallAmount: 0n },
    ]);
    let pc = await viem.getPublicClient();
    let { logs } = await pc.waitForTransactionReceipt({ hash: tx });
    const decodedLog = decodeEventLog({
        abi: CREATEX_ABI,
        topics: logs[1].topics,
        data: logs[1].data,
    });
    let deployedAddress = decodedLog.args.newContract;

    // Use the deployer address to back-compute the deployed contract address
    // and store the deployment configuration in deployments.json.
    console.log(` - saving ${name}...`);
    hyperdriveDeploy.deployments.add(
        name,
        "HyperdriveRegistry",
        deployedAddress as Address,
    );
});
