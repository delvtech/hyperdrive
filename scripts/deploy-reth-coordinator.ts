import hre from "hardhat";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { parseEther } from "viem";
dayjs.extend(duration);

const ADMIN = "0x25a6592F1eaA22cD7BFc590A90d56FbB765b1Edc";
const GOVERNANCE = "0x25a6592F1eaA22cD7BFc590A90d56FbB765b1Edc";
const LIDO_ADDRESS = "";

async function main() {
  /**
   * RETH
   */

  const rethCore = await hre.viem.deployContract("RETHHyperdriveCoreDeployer");
  await hre.deployments.save("RETHHyperdriveCoreDeployer", rethCore);
  await hre.run("verify:verify", {
    address: rethCore.address,
    constructorArguments: [],
    network: hre.network.name,
  });

  const rethTarget0Deployer = await hre.viem.deployContract(
    "RETHTarget0Deployer",
  );
  await hre.deployments.save("RETHTarget0Deployer", rethTarget0Deployer);
  await hre.run("verify:verify", {
    address: rethTarget0Deployer.address,
    constructorArguments: [],
    network: hre.network.name,
  });

  const rethTarget1Deployer = await hre.viem.deployContract(
    "RETHTarget1Deployer",
  );
  await hre.deployments.save("RETHTarget1Deployer", rethTarget1Deployer);
  await hre.run("verify:verify", {
    address: rethTarget1Deployer.address,
    constructorArguments: [],
    network: hre.network.name,
  });

  const rethTarget2Deployer = await hre.viem.deployContract(
    "RETHTarget2Deployer",
  );
  await hre.deployments.save("RETHTarget2Deployer", rethTarget2Deployer);
  await hre.run("verify:verify", {
    address: rethTarget2Deployer.address,
    constructorArguments: [],
    network: hre.network.name,
  });
  const rethTarget3Deployer = await hre.viem.deployContract(
    "RETHTarget3Deployer",
  );
  await hre.deployments.save("RETHTarget3Deployer", rethTarget3Deployer);
  await hre.run("verify:verify", {
    address: rethTarget3Deployer.address,
    constructorArguments: [],
    network: hre.network.name,
  });
  const rethTarget4Deployer = await hre.viem.deployContract(
    "RETHTarget4Deployer",
  );
  await hre.deployments.save("RETHTarget4Deployer", rethTarget4Deployer);
  await hre.run("verify:verify", {
    address: rethTarget4Deployer.address,
    constructorArguments: [],
    network: hre.network.name,
  });

  const mockReth = await hre.viem.deployContract("MockRocketPool", [
    parseEther("0.035"),
    ADMIN,
    true,
    parseEther("500"),
  ]);
  await hre.deployments.save("MockRocketPool", mockReth);
  await hre.run("verify:verify", {
    address: mockReth.address,
    constructorArguments: [parseEther("0.035"), ADMIN, true, parseEther("500")],
    network: hre.network.name,
  });

  const rethCoordinator = await hre.viem.deployContract(
    "RETHHyperdriveDeployerCoordinator",
    [
      hyperdriveFactory.address,
      rethCore.address,
      rethTarget0Deployer.address,
      rethTarget1Deployer.address,
      rethTarget2Deployer.address,
      rethTarget3Deployer.address,
      rethTarget4Deployer.address,
      mockReth.address,
    ],
  );
  await hre.deployments.save(
    "RETHHyperdriveDeployerCoordinator",
    rethCoordinator,
  );
  await hre.run("verify:verify", {
    address: rethCoordinator.address,
    constructorArguments: [],
    network: hre.network.name,
  });
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
