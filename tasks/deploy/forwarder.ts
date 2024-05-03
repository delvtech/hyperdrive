import { task, types } from "hardhat/config";
import { Deployments } from "./deployments";
import { DeploySaveParams } from "./save";

export type DeployForwarderParams = {
    overwrite?: boolean;
};

task(
    "deploy:forwarder",
    "deploys the ERC20ForwarderFactory to the configured chain",
)
    .addOptionalParam(
        "overwrite",
        "overwrite deployment artifacts if they exist",
        false,
        types.boolean,
    )
    .setAction(
        async (
            { overwrite }: DeployForwarderParams,
            { run, network, viem, hyperdrive },
        ) => {
            const contractName = "ERC20ForwarderFactory";
            // Skip if deployed and overwrite=false.
            if (
                !overwrite &&
                Deployments.get().byNameSafe(contractName, network.name)
            ) {
                console.log(`${contractName} already deployed`);
                return;
            }
            // Deploy the ERC20ForwarderFactory
            console.log(`deploying ${contractName}...`);
            const linkerFactory = await viem.deployContract(contractName, []);
            await run("deploy:save", {
                name: contractName,
                args: [],
                abi: linkerFactory.abi,
                address: linkerFactory.address,
                contract: contractName,
            } as DeploySaveParams);
        },
    );
