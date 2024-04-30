import { task, types } from "hardhat/config";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { DeployCoordinatorsBaseParams } from "./shared";
dayjs.extend(duration);

export type DeployCoordinatorsERC4626Params = {};

task(
  "deploy:coordinators:erc4626",
  "deploys the ERC4626 deployment coordinator",
).setAction(
  async (
    {}: DeployCoordinatorsERC4626Params,
    { run, viem, deployments, getNamedAccounts },
  ) => {
    // Deploy the core deployer and all targets
    await run("deploy:coordinators:shared", {
      prefix: "erc4626",
    } as DeployCoordinatorsBaseParams);

    let factory = await deployments.get("HyperdriveFactory");
    let factoryAddress = factory.address as `0x${string}`;

    // Deploy the coordinator
    console.log("deploying ERC4626HyperdriveDeployerCoordinator...");
    let args = [
      factoryAddress,
      (await deployments.get("ERC4626HyperdriveCoreDeployer"))
        .address as `0x${string}`,
      (await deployments.get("ERC4626Target0Deployer"))
        .address as `0x${string}`,
      (await deployments.get("ERC4626Target1Deployer"))
        .address as `0x${string}`,
      (await deployments.get("ERC4626Target2Deployer"))
        .address as `0x${string}`,
      (await deployments.get("ERC4626Target3Deployer"))
        .address as `0x${string}`,
      (await deployments.get("ERC4626Target4Deployer"))
        .address as `0x${string}`,
    ];
    let erc4626Coordinator = await viem.deployContract(
      "ERC4626HyperdriveDeployerCoordinator",
      args as any,
    );
    await deployments.save("ERC4626HyperdriveDeployerCoordinator", {
      ...erc4626Coordinator,
      args,
    });
    await run("deploy:verify", {
      name: "ERC4626HyperdriveDeployerCoordinator",
    });

    // Register the coordinator with governance if the factory's governance address is the deployer's address
    let factoryContract = await viem.getContractAt(
      "HyperdriveFactory",
      factoryAddress,
    );
    let factoryGovernanceAddress = await factoryContract.read.governance();
    let deployer = (await getNamedAccounts())["deployer"];
    if (deployer === factoryGovernanceAddress) {
      await factoryContract.write.addDeployerCoordinator([
        erc4626Coordinator.address,
      ]);
    }
  },
);
