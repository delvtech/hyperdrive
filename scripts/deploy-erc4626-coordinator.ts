import hre from "hardhat";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { parseEther } from "viem";
dayjs.extend(duration);

const ADMIN = "0x25a6592F1eaA22cD7BFc590A90d56FbB765b1Edc";
const GOVERNANCE = "0x25a6592F1eaA22cD7BFc590A90d56FbB765b1Edc";
const LIDO_ADDRESS = "";

async function main() {
  const factoryAddress = (await hre.deployments.get("HyperdriveFactory"))
    .address as `0x${string}`;

  /**
   * ERC4626
   */

  const erc4626Core = await hre.viem.deployContract(
    "ERC4626HyperdriveCoreDeployer",
  );
  await hre.deployments.save("ERC4626HyperdriveCoreDeployer", erc4626Core);
  await hre.run("verify:verify", {
    address: erc4626Core.address,
    constructorArguments: [],
    network: hre.network.name,
  });

  const erc4626Target0Deployer = await hre.viem.deployContract(
    "ERC4626Target0Deployer",
  );
  await hre.deployments.save("ERC4626Target0Deployer", erc4626Target0Deployer);
  await hre.run("verify:verify", {
    address: erc4626Target0Deployer.address,
    constructorArguments: [],
    network: hre.network.name,
  });

  const erc4626Target1Deployer = await hre.viem.deployContract(
    "ERC4626Target1Deployer",
  );
  await hre.deployments.save("ERC4626Target1Deployer", erc4626Target1Deployer);
  await hre.run("verify:verify", {
    address: erc4626Target1Deployer.address,
    constructorArguments: [],
    network: hre.network.name,
  });

  const erc4626Target2Deployer = await hre.viem.deployContract(
    "ERC4626Target2Deployer",
  );
  await hre.deployments.save("ERC4626Target2Deployer", erc4626Target2Deployer);
  await hre.run("verify:verify", {
    address: erc4626Target2Deployer.address,
    constructorArguments: [],
    network: hre.network.name,
  });

  const erc4626Target3Deployer = await hre.viem.deployContract(
    "ERC4626Target3Deployer",
  );
  await hre.deployments.save("ERC4626Target3Deployer", erc4626Target3Deployer);
  await hre.run("verify:verify", {
    address: erc4626Target3Deployer.address,
    constructorArguments: [],
    network: hre.network.name,
  });

  const erc4626Target4Deployer = await hre.viem.deployContract(
    "ERC4626Target4Deployer",
  );
  await hre.deployments.save("ERC4626Target4Deployer", erc4626Target4Deployer);
  await hre.run("verify:verify", {
    address: erc4626Target4Deployer.address,
    constructorArguments: [],
    network: hre.network.name,
  });

  const erc4626Coordinator = await hre.viem.deployContract(
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
  await hre.deployments.save(
    "ERC4626HyperdriveDeployerCoordinator",
    erc4626Coordinator,
  );
  await hre.run("verify:verify", {
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
    network: hre.network.name,
  });
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
