import { task, types } from "hardhat/config";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
dayjs.extend(duration);
import { parseEther, toFunctionSelector, zeroAddress } from "viem";
import { zAddress } from "../utils";
import { z } from "zod";
import { DeployCoordinatorsBaseParams } from "./shared";

export let zStETHCoordinatorDeployConfig = z.object({
  lido: zAddress.optional(),
});

export type StETHCoordinatorDeployConfigInput = z.input<
  typeof zStETHCoordinatorDeployConfig
>;

export type StETHCoordinatorDeployConfig = z.infer<
  typeof zStETHCoordinatorDeployConfig
>;

export type DeployCoordinatorsStethParams = {
  admin?: string;
};

task("deploy:coordinators:steth", "deploys the STETH deployment coordinator")
  .addOptionalParam("admin", "admin address", undefined, types.string)
  .setAction(
    async (
      { admin }: DeployCoordinatorsStethParams,
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
      let lido = hardhatConfig.networks[network.name].coordinators?.lido;
      if (!lido?.length) {
        let mockLido = await viem.deployContract("MockLido", [
          parseEther("0.035"),
          admin as `0x${string}`,
          true,
          parseEther("500"),
        ]);
        await deployments.save("MockLido", {
          ...mockLido,
          args: [
            parseEther("0.035"),
            admin as `0x${string}`,
            true,
            parseEther("500"),
          ],
        });
        await run("deploy:verify", {
          name: "MockLido",
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
        await mockLido.write.submit([zeroAddress], {
          value: parseEther("0.001"),
        });
        lido = mockLido.address;
      }

      // Deploy the core deployer and all targets
      await run("deploy:coordinators:shared", {
        prefix: "steth",
      } as DeployCoordinatorsBaseParams);

      // Deploy the coordinator
      console.log("deploying StETHHyperdriveDeployerCoordinator...");
      let args = [
        factoryAddress,
        (await deployments.get("StETHHyperdriveCoreDeployer"))
          .address as `0x${string}`,
        (await deployments.get("StETHTarget0Deployer"))
          .address as `0x${string}`,
        (await deployments.get("StETHTarget1Deployer"))
          .address as `0x${string}`,
        (await deployments.get("StETHTarget2Deployer"))
          .address as `0x${string}`,
        (await deployments.get("StETHTarget3Deployer"))
          .address as `0x${string}`,
        (await deployments.get("StETHTarget4Deployer"))
          .address as `0x${string}`,
        lido,
      ];
      let stethCoordinator = await viem.deployContract(
        "StETHHyperdriveDeployerCoordinator",
        args as any,
      );
      await deployments.save("StETHHyperdriveDeployerCoordinator", {
        ...stethCoordinator,
        args,
      });
      await run("deploy:verify", {
        name: "StETHHyperdriveDeployerCoordinator",
      });

      // Register the coordinator with governance if the factory's governance address is the deployer's address
      let factoryContract = await viem.getContractAt(
        "HyperdriveFactory",
        factoryAddress,
      );
      let factoryGovernanceAddress = await factoryContract.read.governance();
      let deployer = (await getNamedAccounts())["deployer"];
      if (deployer === factoryGovernanceAddress) {
        console.log("adding StETHHyperdriveDeployerCoordinator to factory");
        await factoryContract.write.addDeployerCoordinator([
          stethCoordinator.address,
        ]);
      }
    },
  );
