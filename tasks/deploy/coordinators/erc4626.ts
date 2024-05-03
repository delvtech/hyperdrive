import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { task, types } from "hardhat/config";
import { Deployments } from "../deployments";
import { DeploySaveParams } from "../save";
import { DeployCoordinatorsBaseParams } from "./shared";
dayjs.extend(duration);

export type DeployCoordinatorsERC4626Params = { overwrite?: boolean };

task(
    "deploy:coordinators:erc4626",
    "deploys the ERC4626 deployment coordinator",
)
    .addOptionalParam(
        "overwrite",
        "overwrite deployment artifacts if they exist",
        false,
        types.boolean,
    )
    .setAction(
        async (
            { overwrite }: DeployCoordinatorsERC4626Params,
            { run, viem, getNamedAccounts, network },
        ) => {
            if (
                !overwrite &&
                Deployments.get().byNameSafe(
                    "ERC4626HyperdriveCoreDeployer",
                    network.name,
                )
            ) {
                console.log(
                    `ERC4626HyperdriveDeployerCoordinator already deployed`,
                );
                return;
            }

            // Deploy the core deployer and all targets
            await run("deploy:coordinators:shared", {
                prefix: "erc4626",
            } as DeployCoordinatorsBaseParams);

            let factory = Deployments.get().byName(
                "HyperdriveFactory",
                network.name,
            );
            let factoryAddress = factory.address as `0x${string}`;

            // Deploy the coordinator
            console.log("deploying ERC4626HyperdriveDeployerCoordinator...");
            let args = [
                factoryAddress,
                Deployments.get().byName(
                    "ERC4626HyperdriveCoreDeployer",
                    network.name,
                ).address as `0x${string}`,
                Deployments.get().byName("ERC4626Target0Deployer", network.name)
                    .address as `0x${string}`,
                Deployments.get().byName("ERC4626Target1Deployer", network.name)
                    .address as `0x${string}`,
                Deployments.get().byName("ERC4626Target2Deployer", network.name)
                    .address as `0x${string}`,
                Deployments.get().byName("ERC4626Target3Deployer", network.name)
                    .address as `0x${string}`,
                Deployments.get().byName("ERC4626Target4Deployer", network.name)
                    .address as `0x${string}`,
            ];
            let erc4626Coordinator = await viem.deployContract(
                "ERC4626HyperdriveDeployerCoordinator",
                args as any,
            );
            await run("deploy:save", {
                name: "ERC4626HyperdriveDeployerCoordinator",
                args: args,
                abi: erc4626Coordinator.abi,
                address: erc4626Coordinator.address,
                contract: "ERC4626HyperdriveDeployerCoordinator",
            } as DeploySaveParams);

            // Register the coordinator with governance if the factory's governance address is the deployer's address
            let factoryContract = await viem.getContractAt(
                "HyperdriveFactory",
                factoryAddress,
            );
            let factoryGovernanceAddress =
                await factoryContract.read.governance();
            let deployer = (await getNamedAccounts())["deployer"];
            if (deployer === factoryGovernanceAddress) {
                console.log(
                    "adding ERC4626HyperdriveDeployerCoordinator to factory",
                );
                await factoryContract.write.addDeployerCoordinator([
                    erc4626Coordinator.address,
                ]);
            }
        },
    );
