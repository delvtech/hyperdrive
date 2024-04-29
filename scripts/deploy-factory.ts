import hre from "hardhat";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { parseEther } from "viem";
dayjs.extend(duration);

const ADMIN = "0x25a6592F1eaA22cD7BFc590A90d56FbB765b1Edc";
const GOVERNANCE = "0x25a6592F1eaA22cD7BFc590A90d56FbB765b1Edc";
const LIDO_ADDRESS = "";

async function main() {
  const linkerFactory = await hre.viem.deployContract(
    "ERC20ForwarderFactory",
    [],
  );
  await hre.deployments.save("ERC20ForwarderFactory", linkerFactory);
  await hre.run("verify:verify", {
    address: linkerFactory.address,
    constructorArguments: [],
    network: hre.network.name,
  });

  /**
   * Factory
   */

  const factoryConfig = {
    governance: "0x25a6592F1eaA22cD7BFc590A90d56FbB765b1Edc",
    hyperdriveGovernance: "0x25a6592F1eaA22cD7BFc590A90d56FbB765b1Edc",
    defaultPausers: ["0x25a6592F1eaA22cD7BFc590A90d56FbB765b1Edc"],
    feeCollector: "0x25a6592F1eaA22cD7BFc590A90d56FbB765b1Edc",
    sweepCollector: "0x25a6592F1eaA22cD7BFc590A90d56FbB765b1Edc",
    checkpointDurationResolution: BigInt(
      dayjs.duration(8, "hours").asSeconds(),
    ),
    minCheckpointDuration: BigInt(dayjs.duration(24, "hours").asSeconds()),
    maxCheckpointDuration: BigInt(dayjs.duration(24, "hours").asSeconds()),
    minPositionDuration: BigInt(dayjs.duration(7, "days").asSeconds()),
    maxPositionDuration: BigInt(dayjs.duration(30, "days").asSeconds()),
    minFixedAPR: parseEther("0.0100"),
    maxFixedAPR: parseEther("0.6000"),
    minTimeStretchAPR: parseEther("0.0100"),
    maxTimeStretchAPR: parseEther("0.6000"),
    minFees: {
      curve: parseEther("0.001"),
      flat: parseEther("0.0001"),
      governanceLP: parseEther("0.1500"),
      governanceZombie: parseEther("0.0300"),
    },
    maxFees: {
      curve: parseEther("0.01"),
      flat: parseEther("0.001"),
      governanceLP: parseEther("0.1500"),
      governanceZombie: parseEther("0.0300"),
    },
    linkerFactory: linkerFactory.address,
    linkerCodeHash: await linkerFactory.read.ERC20LINK_HASH(),
  };
  const hyperdriveFactory = await hre.viem.deployContract("HyperdriveFactory", [
    factoryConfig,
    "factory",
  ]);
  await hre.deployments.save("HyperdriveFactory", hyperdriveFactory);
  await hre.run("verify:verify", {
    address: hyperdriveFactory.address,
    constructorArguments: [],
    network: hre.network.name,
  });

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
      hyperdriveFactory.address,
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
      hyperdriveFactory.address,
      erc4626Core.address,
      erc4626Target0Deployer.address,
      erc4626Target1Deployer.address,
      erc4626Target2Deployer.address,
      erc4626Target3Deployer.address,
      erc4626Target4Deployer.address,
    ],
    network: hre.network.name,
  });

  /**
   * STETH
   */

  const stethCore = await hre.viem.deployContract(
    "StETHHyperdriveCoreDeployer",
  );
  await hre.deployments.save("StETHHyperdriveCoreDeployer", stethCore);
  await hre.run("verify:verify", {
    address: stethCore.address,
    constructorArguments: [],
    network: hre.network.name,
  });

  const stethTarget0Deployer = await hre.viem.deployContract(
    "StETHTarget0Deployer",
  );
  await hre.deployments.save("StETHTarget0Deployer", stethTarget0Deployer);
  await hre.run("verify:verify", {
    address: stethTarget0Deployer.address,
    constructorArguments: [],
    network: hre.network.name,
  });

  const stethTarget1Deployer = await hre.viem.deployContract(
    "StETHTarget1Deployer",
  );
  await hre.deployments.save("StETHTarget1Deployer", stethTarget1Deployer);
  await hre.run("verify:verify", {
    address: stethTarget1Deployer.address,
    constructorArguments: [],
    network: hre.network.name,
  });

  const stethTarget2Deployer = await hre.viem.deployContract(
    "StETHTarget2Deployer",
  );
  await hre.deployments.save("StETHTarget2Deployer", stethTarget2Deployer);
  await hre.run("verify:verify", {
    address: stethTarget2Deployer.address,
    constructorArguments: [],
    network: hre.network.name,
  });
  const stethTarget3Deployer = await hre.viem.deployContract(
    "StETHTarget3Deployer",
  );
  await hre.deployments.save("StETHTarget3Deployer", stethTarget3Deployer);
  await hre.run("verify:verify", {
    address: stethTarget3Deployer.address,
    constructorArguments: [],
    network: hre.network.name,
  });
  const stethTarget4Deployer = await hre.viem.deployContract(
    "StETHTarget4Deployer",
  );
  await hre.deployments.save("StETHTarget4Deployer", stethTarget4Deployer);
  await hre.run("verify:verify", {
    address: stethTarget4Deployer.address,
    constructorArguments: [],
    network: hre.network.name,
  });

  const mockLido = await hre.viem.deployContract("MockLido", [
    parseEther("0.035"),
    ADMIN,
    true,
    parseEther("500"),
  ]);
  await hre.deployments.save("MockLido", mockLido);
  await hre.run("verify:verify", {
    address: mockLido.address,
    constructorArguments: [parseEther("0.035"), ADMIN, true, parseEther("500")],
    network: hre.network.name,
  });

  const stethCoordinator = await hre.viem.deployContract(
    "StETHHyperdriveDeployerCoordinator",
    [
      hyperdriveFactory.address,
      stethCore.address,
      stethTarget0Deployer.address,
      stethTarget1Deployer.address,
      stethTarget2Deployer.address,
      stethTarget3Deployer.address,
      stethTarget4Deployer.address,
      mockLido.address,
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
