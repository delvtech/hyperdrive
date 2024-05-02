import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { task, types } from "hardhat/config";
import { parseEther, toFunctionSelector, zeroAddress } from "viem";
import { z } from "zod";
import { Deployments } from "../deployments";
import { DeploySaveParams } from "../save";
import { zAddress } from "../types";
import { DeployCoordinatorsBaseParams } from "./shared";
dayjs.extend(duration);

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
  overwrite?: boolean;
};

task("deploy:coordinators:steth", "deploys the STETH deployment coordinator")
  .addOptionalParam("admin", "admin address", undefined, types.string)
  .addOptionalParam(
    "overwrite",
    "overwrite deployment artifacts if they exist",
    false,
    types.boolean,
  )
  .setAction(
    async (
      { admin, overwrite }: DeployCoordinatorsStethParams,
      { run, network, viem, getNamedAccounts, config: hardhatConfig },
    ) => {
      if (
        !overwrite &&
        Deployments.get().byNameSafe(
          "StETHHyperdriveCoreDeployer",
          network.name,
        )
      ) {
        console.log(`StETHHyperdriveDeployerCoordinator already deployed`);
        return;
      }
      // Retrieve the HyperdriveFactory deployment artifact for the current network
      let factory = await Deployments.get().byName(
        "HyperdriveFactory",
        network.name,
      );
      let factoryAddress = factory.address as `0x${string}`;

      // Set the admin address to the deployer address if one was not provided
      if (!admin?.length) admin = (await getNamedAccounts())["deployer"];

      // Deploy a mock Lido contract if no adress was provided
      let lido =
        hardhatConfig.networks[network.name].coordinators?.lido ??
        Deployments.get().byNameSafe("MockLido", network.name)?.address;
      if (!lido?.length) {
        let mockLido = await viem.deployContract("MockLido", [
          parseEther("0.035"),
          admin as `0x${string}`,
          true,
          parseEther("500"),
        ]);
        await run("deploy:save", {
          name: "MockLido",
          args: [
            parseEther("0.035"),
            admin as `0x${string}`,
            true,
            parseEther("500"),
          ],
          abi: mockLido.abi,
          address: mockLido.address,
          contract: "MockLido",
        } as DeploySaveParams);

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

      // Deploy the core deployer and all target deployers.
      await run("deploy:coordinators:shared", {
        prefix: "steth",
      } as DeployCoordinatorsBaseParams);

      // Deploy the coordinator
      console.log("deploying StETHHyperdriveDeployerCoordinator...");
      let args = [
        factoryAddress,
        Deployments.get().byName("StETHHyperdriveCoreDeployer", network.name)
          .address as `0x${string}`,
        Deployments.get().byName("StETHTarget0Deployer", network.name)
          .address as `0x${string}`,
        Deployments.get().byName("StETHTarget1Deployer", network.name)
          .address as `0x${string}`,
        Deployments.get().byName("StETHTarget2Deployer", network.name)
          .address as `0x${string}`,
        Deployments.get().byName("StETHTarget3Deployer", network.name)
          .address as `0x${string}`,
        Deployments.get().byName("StETHTarget4Deployer", network.name)
          .address as `0x${string}`,
        lido,
      ];
      let stethCoordinator = await viem.deployContract(
        "StETHHyperdriveDeployerCoordinator",
        args as any,
      );
      await run("deploy:save", {
        name: "StETHHyperdriveDeployerCoordinator",
        args,
        abi: stethCoordinator.abi,
        address: stethCoordinator.address,
        contract: "StETHHyperdriveDeployerCoordinator",
      } as DeploySaveParams);

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
