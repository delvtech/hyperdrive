import { task, types } from "hardhat/config";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
dayjs.extend(duration);
import { parseEther, toFunctionSelector } from "viem";

task("deploy:coordinators:steth", "deploys the STETH deployment coordinator")
  .addOptionalParam(
    "lido",
    "address of the lido contract",
    undefined,
    types.string,
  )
  .addOptionalParam("admin", "admin address", undefined, types.string)
  .setAction(
    async (
      { lido, admin }: { lido?: string; admin?: string },
      { deployments, run, network, viem, getNamedAccounts },
    ) => {
      // Retrieve the HyperdriveFactory deployment artifact for the current network
      console.log("retrieving factory deployment artifact...");
      const factory = await deployments.get("HyperdriveFactory");
      const factoryAddress = factory.address as `0x${string}`;

      // Set the admin address to the deployer address if one was not provided
      if (!admin?.length) admin = (await getNamedAccounts())["deployer"];

      // Deploy a mock Lido contract if no adress was provided
      if (!lido?.length) {
        const mockLido = await viem.deployContract("MockLido", [
          parseEther("0.035"),
          admin as `0x${string}`,
          true,
          parseEther("500"),
        ]);
        await deployments.save("MockLido", mockLido);
        await run("verify:verify", {
          address: mockLido.address,
          constructorArguments: [
            parseEther("0.035"),
            admin as `0x${string}`,
            true,
            parseEther("500"),
          ],
          network: network.name,
        });
        // allow minting by the general public
        await mockLido.write.setPublicCapability([
          toFunctionSelector("mint(uint256)"),
          true,
        ]);
        await mockLido.write.setPublicCapability([
          toFunctionSelector("mint(address,uint256)"),
          true,
        ]);
        lido = mockLido.address;
      }

      console.log("deploying steth core deployer...");
      const stethCore = await viem.deployContract(
        "StETHHyperdriveCoreDeployer",
      );
      await deployments.save("StETHHyperdriveCoreDeployer", stethCore);
      await run("verify:verify", {
        address: stethCore.address,
        constructorArguments: [],
        network: network.name,
      });

      console.log("deploying steth target0 deployer...");
      const stethTarget0Deployer = await viem.deployContract(
        "StETHTarget0Deployer",
      );
      await deployments.save("StETHTarget0Deployer", stethTarget0Deployer);
      await run("verify:verify", {
        address: stethTarget0Deployer.address,
        constructorArguments: [],
        network: network.name,
      });

      console.log("deploying steth target1 deployer...");
      const stethTarget1Deployer = await viem.deployContract(
        "StETHTarget1Deployer",
      );
      await deployments.save("StETHTarget1Deployer", stethTarget1Deployer);
      await run("verify:verify", {
        address: stethTarget1Deployer.address,
        constructorArguments: [],
        network: network.name,
      });

      console.log("deploying steth target2 deployer...");
      const stethTarget2Deployer = await viem.deployContract(
        "StETHTarget2Deployer",
      );
      await deployments.save("StETHTarget2Deployer", stethTarget2Deployer);
      await run("verify:verify", {
        address: stethTarget2Deployer.address,
        constructorArguments: [],
        network: network.name,
      });

      console.log("deploying steth target3 deployer...");
      const stethTarget3Deployer = await viem.deployContract(
        "StETHTarget3Deployer",
      );
      await deployments.save("StETHTarget3Deployer", stethTarget3Deployer);
      await run("verify:verify", {
        address: stethTarget3Deployer.address,
        constructorArguments: [],
        network: network.name,
      });

      console.log("deploying steth target4 deployer...");
      const stethTarget4Deployer = await viem.deployContract(
        "StETHTarget4Deployer",
      );
      await deployments.save("StETHTarget4Deployer", stethTarget4Deployer);
      await run("verify:verify", {
        address: stethTarget4Deployer.address,
        constructorArguments: [],
        network: network.name,
      });

      console.log("deploying steth deployer coordinator...");
      const stethCoordinator = await viem.deployContract(
        "StETHHyperdriveDeployerCoordinator",
        [
          factoryAddress,
          stethCore.address,
          stethTarget0Deployer.address,
          stethTarget1Deployer.address,
          stethTarget2Deployer.address,
          stethTarget3Deployer.address,
          stethTarget4Deployer.address,
          lido as `0x${string}`,
        ],
      );
      await deployments.save(
        "StETHHyperdriveDeployerCoordinator",
        stethCoordinator,
      );
      await run("verify:verify", {
        address: stethCoordinator.address,
        constructorArguments: [
          factoryAddress,
          stethCore.address,
          stethTarget0Deployer.address,
          stethTarget1Deployer.address,
          stethTarget2Deployer.address,
          stethTarget3Deployer.address,
          stethTarget4Deployer.address,
          lido as `0x${string}`,
        ],
        network: network.name,
      });
    },
  );
