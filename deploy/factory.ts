import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { parseEther } from "viem";
dayjs.extend(duration);

const ADMIN = "0x25a6592F1eaA22cD7BFc590A90d56FbB765b1Edc";
const GOVERNANCE = "0x25a6592F1eaA22cD7BFc590A90d56FbB765b1Edc";
const LIDO_ADDRESS = "";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();

  const linkerFactory = await deploy("ERC20ForwarderFactory", {
    from: deployer,
  });
  const linkerCodeHash = await (
    await hre.viem.getContractAt(
      "ERC20ForwarderFactory",
      linkerFactory.address as `0x${string}`,
    )
  ).read.ERC20LINK_HASH();
  const hyperdriveFactory = await deploy("HyperdriveFactory", {
    from: deployer,
    args: [
      {
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
        linkerCodeHash,
      },
      "factory",
    ],
  });
  const erc4626Core = await deploy("ERC4626HyperdriveCoreDeployer", {
    from: deployer,
  });
  const erc4626Target0Deployer = await deploy("ERC4626Target0Deployer", {
    from: deployer,
  });
  const erc4626Target1Deployer = await deploy("ERC4626Target1Deployer", {
    from: deployer,
  });
  const erc4626Target2Deployer = await deploy("ERC4626Target2Deployer", {
    from: deployer,
  });
  const erc4626Target3Deployer = await deploy("ERC4626Target3Deployer", {
    from: deployer,
  });
  const erc4626Target4Deployer = await deploy("ERC4626Target4Deployer", {
    from: deployer,
  });
  const erc4626Coordinator = await deploy(
    "ERC4626HyperdriveDeployerCoordinator",
    {
      from: deployer,
      args: [
        hyperdriveFactory.address,
        erc4626Core.address,
        erc4626Target0Deployer.address,
        erc4626Target1Deployer.address,
        erc4626Target2Deployer.address,
        erc4626Target3Deployer.address,
        erc4626Target4Deployer.address,
      ],
    },
  );

  const stethCore = await deploy("StETHHyperdriveCoreDeployer", {
    from: deployer,
  });
  const stethTarget0Deployer = await deploy("StETHTarget0Deployer", {
    from: deployer,
  });
  const stethTarget1Deployer = await deploy("StETHTarget1Deployer", {
    from: deployer,
  });
  const stethTarget2Deployer = await deploy("StETHTarget2Deployer", {
    from: deployer,
  });
  const stethTarget3Deployer = await deploy("StETHTarget3Deployer", {
    from: deployer,
  });
  const stethTarget4Deployer = await deploy("StETHTarget4Deployer", {
    from: deployer,
  });
  const lido =
    hre.network.name == "sepolia"
      ? (
          await deploy("MockLido", {
            from: deployer,
            args: [parseEther("0.035"), ADMIN, true, parseEther("500")],
            log: true,
          })
        ).address
      : LIDO_ADDRESS;
  const stethCoordinator = await deploy("StETHHyperdriveDeployerCoordinator", {
    from: deployer,
    args: [
      hyperdriveFactory.address,
      stethCore.address,
      stethTarget0Deployer.address,
      stethTarget1Deployer.address,
      stethTarget2Deployer.address,
      stethTarget3Deployer.address,
      stethTarget4Deployer.address,
      lido,
    ],
  });
};
export default func;
