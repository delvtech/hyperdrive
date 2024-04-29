import { task, types } from "hardhat/config";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
dayjs.extend(duration);
import { readFile } from "fs/promises";
import { parseEther } from "viem";

task(
  "deploy:coordinators:erc4626",
  "deploys the ERC4626 deployment coordinator",
).setAction(async ({}: {}, { deployments, run, network, viem }) => {
  // Retrieve the HyperdriveFactory deployment artifact for the current network
  console.log("retrieving factory deployment artifact...");
  const factory = await deployments.get("HyperdriveFactory");
  const factoryAddress = factory.address as `0x${string}`;

  console.log("deploying erc4626 core deployer...");
  const erc4626Core = await viem.deployContract(
    "ERC4626HyperdriveCoreDeployer",
  );
  await deployments.save("ERC4626HyperdriveCoreDeployer", erc4626Core);
  await run("verify:verify", {
    address: erc4626Core.address,
    constructorArguments: [],
    network: network.name,
  });

  console.log("deploying erc4626 target0 deployer...");
  const erc4626Target0Deployer = await viem.deployContract(
    "ERC4626Target0Deployer",
  );
  await deployments.save("ERC4626Target0Deployer", erc4626Target0Deployer);
  await run("verify:verify", {
    address: erc4626Target0Deployer.address,
    constructorArguments: [],
    network: network.name,
  });

  console.log("deploying erc4626 target1 deployer...");
  const erc4626Target1Deployer = await viem.deployContract(
    "ERC4626Target1Deployer",
  );
  await deployments.save("ERC4626Target1Deployer", erc4626Target1Deployer);
  await run("verify:verify", {
    address: erc4626Target1Deployer.address,
    constructorArguments: [],
    network: network.name,
  });

  console.log("deploying erc4626 target2 deployer...");
  const erc4626Target2Deployer = await viem.deployContract(
    "ERC4626Target2Deployer",
  );
  await deployments.save("ERC4626Target2Deployer", erc4626Target2Deployer);
  await run("verify:verify", {
    address: erc4626Target2Deployer.address,
    constructorArguments: [],
    network: network.name,
  });

  console.log("deploying erc4626 target3 deployer...");
  const erc4626Target3Deployer = await viem.deployContract(
    "ERC4626Target3Deployer",
  );
  await deployments.save("ERC4626Target3Deployer", erc4626Target3Deployer);
  await run("verify:verify", {
    address: erc4626Target3Deployer.address,
    constructorArguments: [],
    network: network.name,
  });

  console.log("deploying erc4626 target4 deployer...");
  const erc4626Target4Deployer = await viem.deployContract(
    "ERC4626Target4Deployer",
  );
  await deployments.save("ERC4626Target4Deployer", erc4626Target4Deployer);
  await run("verify:verify", {
    address: erc4626Target4Deployer.address,
    constructorArguments: [],
    network: network.name,
  });

  console.log("deploying erc4626 deployer coordinator...");
  const erc4626Coordinator = await viem.deployContract(
    "ERC4626HyperdriveDeployerCoordinator",
    [
      factoryAddress,
      erc4626Core.address,
      erc4626Target0Deployer.address,
      erc4626Target1Deployer.address,
      erc4626Target2Deployer.address,
      erc4626Target3Deployer.address,
      erc4626Target4Deployer.address,
    ],
  );
  await deployments.save(
    "ERC4626HyperdriveDeployerCoordinator",
    erc4626Coordinator,
  );
  await run("verify:verify", {
    address: erc4626Coordinator.address,
    constructorArguments: [
      factoryAddress,
      erc4626Core.address,
      erc4626Target0Deployer.address,
      erc4626Target1Deployer.address,
      erc4626Target2Deployer.address,
      erc4626Target3Deployer.address,
      erc4626Target4Deployer.address,
    ],
    network: network.name,
  });
});
