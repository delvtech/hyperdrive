import { task, types } from "hardhat/config";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
dayjs.extend(duration);
import { parseEther, toFunctionSelector } from "viem";
import { z } from "zod";
import { zAddress } from "../utils";
import { DeployCoordinatorsBaseParams } from "./shared";

export let zRETHCoordinatorDeployConfig = z.object({
  reth: zAddress.optional(),
});

export type RETHCoordinatorDeployConfigInput = z.input<
  typeof zRETHCoordinatorDeployConfig
>;

export type RETHCoordinatorDeployConfig = z.infer<
  typeof zRETHCoordinatorDeployConfig
>;

export type DeployCoordinatorsRethParams = {
  admin?: string;
  overwrite?: boolean;
};

task("deploy:coordinators:reth", "deploys the RETH deployment coordinator")
  .addOptionalParam("admin", "admin address", undefined, types.string)
  .addOptionalParam(
    "overwrite",
    "overwrite deployment artifacts if they exist",
    false,
    types.boolean,
  )
  .setAction(
    async (
      { admin, overwrite }: DeployCoordinatorsRethParams,
      {
        deployments,
        run,
        network,
        viem,
        getNamedAccounts,
        config: hardhatConfig,
      },
    ) => {
      let artifacts = await deployments.all();
      if (!overwrite && artifacts["HyperdriveFactory"]) {
        console.log(`HyperdriveFactory already deployed`);
        return;
      }
      // Retrieve the HyperdriveFactory deployment artifact for the current network
      let factory = await deployments.get("HyperdriveFactory");
      let factoryAddress = factory.address as `0x${string}`;

      // Set the admin address to the deployer address if one was not provided
      if (!admin?.length) admin = (await getNamedAccounts())["deployer"];

      // Deploy a mock Lido contract if no adress was provided
      let reth = hardhatConfig.networks[network.name].coordinators?.reth;
      if (!reth?.length) {
        let mockRocketPool = await viem.deployContract("MockRocketPool", [
          parseEther("0.035"),
          admin as `0x${string}`,
          true,
          parseEther("500"),
        ]);
        await deployments.save("MockRocketPool", {
          ...mockRocketPool,
          args: [
            parseEther("0.035"),
            admin as `0x${string}`,
            true,
            parseEther("500"),
          ],
        });
        await run("deploy:verify", {
          name: "MockRocketPool",
        });
        // allow minting by the general public
        await mockRocketPool.write.setPublicCapability([
          toFunctionSelector("mint(uint256)"),
          true,
        ]);
        await mockRocketPool.write.setPublicCapability([
          toFunctionSelector("mint(address,uint256)"),
          true,
        ]);
        reth = mockRocketPool.address;
      }

      // Deploy the core deployer and all targets
      await run("deploy:coordinators:shared", {
        prefix: "reth",
      } as DeployCoordinatorsBaseParams);

      // Deploy the coordinator
      console.log("deploying RETHHyperdriveDeployerCoordinator...");
      let args = [
        factoryAddress,
        (await deployments.get("RETHHyperdriveCoreDeployer"))
          .address as `0x${string}`,
        (await deployments.get("RETHTarget0Deployer")).address as `0x${string}`,
        (await deployments.get("RETHTarget1Deployer")).address as `0x${string}`,
        (await deployments.get("RETHTarget2Deployer")).address as `0x${string}`,
        (await deployments.get("RETHTarget3Deployer")).address as `0x${string}`,
        (await deployments.get("RETHTarget4Deployer")).address as `0x${string}`,
        reth,
      ];
      let rethCoordinator = await viem.deployContract(
        "RETHHyperdriveDeployerCoordinator",
        args as any,
      );
      await deployments.save("RETHHyperdriveDeployerCoordinator", {
        ...rethCoordinator,
        args,
      });
      await run("deploy:verify", {
        name: "RETHHyperdriveDeployerCoordinator",
      });

      // Register the coordinator with governance if the factory's governance address is the deployer's address
      let factoryContract = await viem.getContractAt(
        "HyperdriveFactory",
        factoryAddress,
      );
      let factoryGovernanceAddress = await factoryContract.read.governance();
      let deployer = (await getNamedAccounts())["deployer"];
      if (deployer === factoryGovernanceAddress) {
        console.log("adding RETHHyperdriveDeployerCoordinator to factory");
        await factoryContract.write.addDeployerCoordinator([
          rethCoordinator.address,
        ]);
      }
    },
  );
