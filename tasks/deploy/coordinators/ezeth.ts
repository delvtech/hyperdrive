import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { task, types } from "hardhat/config";
import { parseEther, toFunctionSelector, zeroAddress } from "viem";
import { z } from "zod";
import { zAddress } from "../types";
import { DeployCoordinatorsBaseParams } from "./shared";
dayjs.extend(duration);

export let zEzETHCoordinatorDeployConfig = z.object({
  ezeth: zAddress.optional(),
});

export type EzETHCoordinatorDeployConfigInput = z.input<
  typeof zEzETHCoordinatorDeployConfig
>;

export type EzETHCoordinatorDeployConfig = z.infer<
  typeof zEzETHCoordinatorDeployConfig
>;

export type DeployCoordinatorsEzethParams = {
  admin?: string;
};

task("deploy:coordinators:ezeth", "deploys the EzETHdeployment coordinator")
  .addOptionalParam("admin", "admin address", undefined, types.string)
  .setAction(
    async (
      { admin }: DeployCoordinatorsEzethParams,
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
      let factory = await deployments.get("HyperdriveFactory");
      let factoryAddress = factory.address as `0x${string}`;

      // Set the admin address to the deployer address if one was not provided
      if (!admin?.length) admin = (await getNamedAccounts())["deployer"];

      // Deploy a mock Lido contract if no adress was provided
      let ezeth = hardhatConfig.networks[network.name].coordinators?.ezeth;
      if (!ezeth?.length) {
        let mockEzEth = await viem.deployContract("MockEzEthPool", [
          parseEther("0.035"),
          admin as `0x${string}`,
          true,
          parseEther("500"),
        ]);
        await deployments.save("MockEzEthPool", {
          ...mockEzEth,
          args: [
            parseEther("0.035"),
            admin as `0x${string}`,
            true,
            parseEther("500"),
          ],
        });
        await run("deploy:verify", {
          name: "MockEzEthPool",
        });
        // allow minting by the general public
        await mockEzEth.write.setPublicCapability([
          toFunctionSelector("mint(uint256)"),
          true,
        ]);
        await mockEzEth.write.setPublicCapability([
          toFunctionSelector("mint(address,uint256)"),
          true,
        ]);
        await mockEzEth.write.submit([zeroAddress], {
          value: parseEther("0.001"),
        });
        ezeth = mockEzEth.address;
      }

      // Deploy the core deployer and all targets
      await run("deploy:coordinators:shared", {
        prefix: "ezeth",
      } as DeployCoordinatorsBaseParams);

      // Deploy the coordinator
      console.log("deploying EzETHHyperdriveDeployerCoordinator...");
      let args = [
        factoryAddress,
        (await deployments.get("EzETHHyperdriveCoreDeployer"))
          .address as `0x${string}`,
        (await deployments.get("EzETHTarget0Deployer"))
          .address as `0x${string}`,
        (await deployments.get("EzETHTarget1Deployer"))
          .address as `0x${string}`,
        (await deployments.get("EzETHTarget2Deployer"))
          .address as `0x${string}`,
        (await deployments.get("EzETHTarget3Deployer"))
          .address as `0x${string}`,
        (await deployments.get("EzETHTarget4Deployer"))
          .address as `0x${string}`,
        ezeth,
      ];
      let ezethCoordinator = await viem.deployContract(
        "EzETHHyperdriveDeployerCoordinator",
        args as any,
      );
      await deployments.save("EzETHHyperdriveDeployerCoordinator", {
        ...ezethCoordinator,
        args,
      });
      await run("deploy:verify", {
        name: "EzETHHyperdriveDeployerCoordinator",
      });

      // Register the coordinator with governance if the factory's governance address is the deployer's address
      let factoryContract = await viem.getContractAt(
        "HyperdriveFactory",
        factoryAddress,
      );
      let factoryGovernanceAddress = await factoryContract.read.governance();
      let deployer = (await getNamedAccounts())["deployer"];
      if (deployer === factoryGovernanceAddress) {
        console.log("adding EzETHHyperdriveDeployerCoordinator to factory");
        await factoryContract.write.addDeployerCoordinator([
          ezethCoordinator.address,
        ]);
      }
    },
  );
