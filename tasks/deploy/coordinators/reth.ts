import { task, types } from "hardhat/config";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
dayjs.extend(duration);
import { parseEther, toFunctionSelector } from "viem";

export type DeployCoordinatorsRethParams = {
  admin?: string;
};

task("deploy:coordinators:reth", "deploys the RETH deployment coordinator")
  .addOptionalParam("admin", "admin address", undefined, types.string)
  .setAction(
    async (
      { admin }: DeployCoordinatorsRethParams,
      {
        deployments,
        run,
        network,
        viem,
        getNamedAccounts,
        config: hardhatConfig,
      },
    ) => {
      // Retrieve the HyperdriveFactory deployment artifact for the current network
      console.log("retrieving factory deployment artifact...");
      const factory = await deployments.get("HyperdriveFactory");
      const factoryAddress = factory.address as `0x${string}`;

      // Set the admin address to the deployer address if one was not provided
      if (!admin?.length) admin = (await getNamedAccounts())["deployer"];

      // Deploy a mock RETH contract if no adress was provided
      let reth = hardhatConfig.networks[network.name].coordinators?.reth;
      if (!reth?.length) {
        const mockRETH = await viem.deployContract("MockRocketPool", [
          parseEther("0.035"),
          admin as `0x${string}`,
          true,
          parseEther("500"),
        ]);
        await deployments.save("MockRocketPool", mockRETH);
        if (network.name != "hardhat")
          await run("verify:verify", {
            address: mockRETH.address,
            constructorArguments: [
              parseEther("0.035"),
              admin as `0x${string}`,
              true,
              parseEther("500"),
            ],
            network: network.name,
          });
        // allow minting by the general public
        await mockRETH.write.setPublicCapability([
          toFunctionSelector("mint(uint256)"),
          true,
        ]);
        await mockRETH.write.setPublicCapability([
          toFunctionSelector("mint(address,uint256)"),
          true,
        ]);
        reth = mockRETH.address;
      }

      console.log("deploying reth core deployer...");
      const rethCore = await viem.deployContract("RETHHyperdriveCoreDeployer");
      await deployments.save("RETHHyperdriveCoreDeployer", rethCore);
      if (network.name != "hardhat")
        await run("verify:verify", {
          address: rethCore.address,
          constructorArguments: [],
          network: network.name,
        });

      console.log("deploying reth target0 deployer...");
      const rethTarget0Deployer = await viem.deployContract(
        "RETHTarget0Deployer",
      );
      await deployments.save("RETHTarget0Deployer", rethTarget0Deployer);
      if (network.name != "hardhat")
        await run("verify:verify", {
          address: rethTarget0Deployer.address,
          constructorArguments: [],
          network: network.name,
        });

      console.log("deploying reth target1 deployer...");
      const rethTarget1Deployer = await viem.deployContract(
        "RETHTarget1Deployer",
      );
      await deployments.save("RETHTarget1Deployer", rethTarget1Deployer);
      if (network.name != "hardhat")
        await run("verify:verify", {
          address: rethTarget1Deployer.address,
          constructorArguments: [],
          network: network.name,
        });

      console.log("deploying reth target2 deployer...");
      const rethTarget2Deployer = await viem.deployContract(
        "RETHTarget2Deployer",
      );
      await deployments.save("RETHTarget2Deployer", rethTarget2Deployer);
      if (network.name != "hardhat")
        await run("verify:verify", {
          address: rethTarget2Deployer.address,
          constructorArguments: [],
          network: network.name,
        });

      console.log("deploying reth target3 deployer...");
      const rethTarget3Deployer = await viem.deployContract(
        "RETHTarget3Deployer",
      );
      await deployments.save("RETHTarget3Deployer", rethTarget3Deployer);
      if (network.name != "hardhat")
        await run("verify:verify", {
          address: rethTarget3Deployer.address,
          constructorArguments: [],
          network: network.name,
        });

      console.log("deploying reth target4 deployer...");
      const rethTarget4Deployer = await viem.deployContract(
        "RETHTarget4Deployer",
      );
      await deployments.save("RETHTarget4Deployer", rethTarget4Deployer);
      if (network.name != "hardhat")
        await run("verify:verify", {
          address: rethTarget4Deployer.address,
          constructorArguments: [],
          network: network.name,
        });

      console.log("deploying reth deployer coordinator...");
      const rethCoordinator = await viem.deployContract(
        "RETHHyperdriveDeployerCoordinator",
        [
          factoryAddress,
          rethCore.address,
          rethTarget0Deployer.address,
          rethTarget1Deployer.address,
          rethTarget2Deployer.address,
          rethTarget3Deployer.address,
          rethTarget4Deployer.address,
          reth as `0x${string}`,
        ],
      );
      await deployments.save(
        "RETHHyperdriveDeployerCoordinator",
        rethCoordinator,
      );
      if (network.name != "hardhat")
        await run("verify:verify", {
          address: rethCoordinator.address,
          constructorArguments: [
            factoryAddress,
            rethCore.address,
            rethTarget0Deployer.address,
            rethTarget1Deployer.address,
            rethTarget2Deployer.address,
            rethTarget3Deployer.address,
            rethTarget4Deployer.address,
            reth as `0x${string}`,
          ],
          network: network.name,
        });

      // Register the coordinator with governance if the factory's governance address is the deployer's address
      const factoryContract = await viem.getContractAt(
        "HyperdriveFactory",
        factoryAddress,
      );
      const factoryGovernanceAddress = await factoryContract.read.governance();
      const deployer = (await getNamedAccounts())["deployer"];
      if (deployer === factoryGovernanceAddress) {
        await factoryContract.write.addDeployerCoordinator([
          rethCoordinator.address,
        ]);
      }
    },
  );
