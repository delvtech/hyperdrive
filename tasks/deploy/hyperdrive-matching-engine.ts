import { subtask } from "hardhat/config";
import { Address, decodeEventLog, encodeDeployData, encodePacked } from "viem";
import { CREATEX_ABI } from "../../lib/createx/interface/src/lib/constants";
import {
    CREATE_X_FACTORY,
    HYPERDRIVE_MATCHING_ENGINE_SALT,
    HyperdriveDeployBaseTask,
    HyperdriveDeployNamedTaskParams,
    deployCreateX,
} from "./lib";

// Extend params to include the additional constructor arguments
export interface DeployHyperdriveMatchingEngineParams
    extends HyperdriveDeployNamedTaskParams {
    morpho: Address;
}

HyperdriveDeployBaseTask(
    subtask(
        "deploy:hyperdrive-matching-engine",
        "deploys the HyperdriveMatchingEngine contract to the configured chain",
    ),
).setAction(
    async ({ name, morpho }: DeployHyperdriveMatchingEngineParams, hre) => {
        console.log("\nRunning deploy:hyperdrive-matching-engine ...");
        const { hyperdriveDeploy, artifacts, viem, network } = hre;

        // If the network is anvil, we need to deploy the CREATEX factory if it
        // hasn't been deployed before.
        await deployCreateX(hre);

        // Skip if the zap is already deployed
        if (!!hyperdriveDeploy.deployments.byNameSafe(name)) {
            console.log(`skipping ${name}, found existing deployment`);
            return;
        }

        // Assemble the creation code by packing the contract's bytecode with
        // its constructor arguments.
        let artifact = artifacts.readArtifactSync("HyperdriveMatchingEngine");
        let deployData = encodeDeployData({
            abi: artifact.abi,
            bytecode: artifact.bytecode,
            args: [name, morpho],
        });
        let creationCode = encodePacked(["bytes"], [deployData]);

        // Call the Create3 deployer to deploy the contract
        // Note: No initialization data needed since we're using a constructor
        let createXDeployer = await viem.getContractAt(
            "IDeterministicDeployer",
            CREATE_X_FACTORY,
        );
        let tx = await createXDeployer.write.deployCreate3([
            HYPERDRIVE_MATCHING_ENGINE_SALT,
            creationCode,
        ]);
        let { logs } = await pc.waitForTransactionReceipt({ hash: tx });
        const decodedLog = decodeEventLog({
            abi: CREATEX_ABI,
            topics: logs[1].topics,
            data: logs[1].data,
        });
        let deployedAddress = decodedLog.args.newContract;

        // Save the deployment
        console.log(` - saving ${name}...`);
        hyperdriveDeploy.deployments.add(
            name,
            "HyperdriveMatchingEngine",
            deployedAddress as Address,
        );
    },
);
