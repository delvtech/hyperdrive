import hre from "hardhat";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { parseEther, keccak256, toFunctionSelector } from "viem";
import "dotenv/config";
dayjs.extend(duration);

const ADMIN = "0x25a6592F1eaA22cD7BFc590A90d56FbB765b1Edc";
let LIDO_ADDRESS = process.env.LIDO_ADDRESS;

async function main() {
  const factoryAddress = (await hre.deployments.get("HyperdriveFactory"))
    .address as `0x${string}`;

  if (!LIDO_ADDRESS || !LIDO_ADDRESS.length) {
    const mockLido = await hre.viem.deployContract("MockLido", [
      parseEther("0.035"),
      ADMIN,
      true,
      parseEther("500"),
    ]);
    await mockLido.write.setPublicCapability([
      toFunctionSelector("mint(uint256)"),
      true,
    ]);
    await mockLido.write.setPublicCapability([
      toFunctionSelector("mint(address,uint256)"),
      true,
    ]);
    LIDO_ADDRESS = mockLido.address;
  }

  /**
   * STETH
   */

  // core
  const stethCore = await hre.viem.deployContract(
    "StETHHyperdriveCoreDeployer",
  );
  await hre.deployments.save("StETHHyperdriveCoreDeployer", stethCore);
  await hre.run("verify:verify", {
    address: stethCore.address,
    constructorArguments: [],
    network: hre.network.name,
  });

  // target 0
  const stethTarget0Deployer = await hre.viem.deployContract(
    "StETHTarget0Deployer",
  );
  await hre.deployments.save("StETHTarget0Deployer", stethTarget0Deployer);
  await hre.run("verify:verify", {
    address: stethTarget0Deployer.address,
    constructorArguments: [],
    network: hre.network.name,
  });

  // target 1
  const stethTarget1Deployer = await hre.viem.deployContract(
    "StETHTarget1Deployer",
  );
  await hre.deployments.save("StETHTarget1Deployer", stethTarget1Deployer);
  await hre.run("verify:verify", {
    address: stethTarget1Deployer.address,
    constructorArguments: [],
    network: hre.network.name,
  });

  // target 2
  const stethTarget2Deployer = await hre.viem.deployContract(
    "StETHTarget2Deployer",
  );
  await hre.deployments.save("StETHTarget2Deployer", stethTarget2Deployer);
  await hre.run("verify:verify", {
    address: stethTarget2Deployer.address,
    constructorArguments: [],
    network: hre.network.name,
  });

  // target 3
  const stethTarget3Deployer = await hre.viem.deployContract(
    "StETHTarget3Deployer",
  );
  await hre.deployments.save("StETHTarget3Deployer", stethTarget3Deployer);
  await hre.run("verify:verify", {
    address: stethTarget3Deployer.address,
    constructorArguments: [],
    network: hre.network.name,
  });

  // target 4
  const stethTarget4Deployer = await hre.viem.deployContract(
    "StETHTarget4Deployer",
  );
  await hre.deployments.save("StETHTarget4Deployer", stethTarget4Deployer);
  await hre.run("verify:verify", {
    address: stethTarget4Deployer.address,
    constructorArguments: [],
    network: hre.network.name,
  });

  // coordinator
  const stethCoordinator = await hre.viem.deployContract(
    "StETHHyperdriveDeployerCoordinator",
    [
      factoryAddress,
      stethCore.address,
      stethTarget0Deployer.address,
      stethTarget1Deployer.address,
      stethTarget2Deployer.address,
      stethTarget3Deployer.address,
      stethTarget4Deployer.address,
      LIDO_ADDRESS as `0x${string}`,
    ],
  );
  await hre.deployments.save(
    "StETHHyperdriveDeployerCoordinator",
    stethCoordinator,
  );
  await hre.run("verify:verify", {
    address: stethCoordinator.address,
    constructorArguments: [],
    network: hre.network.name,
  });
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
