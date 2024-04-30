import { task, types } from "hardhat/config";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { DeployCoordinatorsERC4626Params } from "./erc4626";
import { DeployCoordinatorsRethParams } from "./reth";
import { DeployCoordinatorsStethParams } from "./steth";
dayjs.extend(duration);

export type DeployCoordinatorsAllParams = DeployCoordinatorsERC4626Params &
  DeployCoordinatorsRethParams &
  DeployCoordinatorsStethParams;

task("deploy:coordinators:all", "deploys all deployment coordinators")
  .addOptionalParam("admin", "admin address", undefined, types.string)
  .setAction(async ({ admin }: DeployCoordinatorsAllParams, { run }) => {
    // deploy the erc4626 coordinator
    console.log("deploying erc4626 deployer coordinator");
    await run("deploy:coordinators:erc4626");

    // deploy the reth coordinator
    console.log("deploying reth deployer coordinator");
    await run("deploy:coordinators:reth", {
      admin,
    } as DeployCoordinatorsRethParams);

    // deploy the steth coordinator
    console.log("deploying steth deployer coordinator");
    await run("deploy:coordinators:steth", {
      admin,
    } as DeployCoordinatorsStethParams);
  });
