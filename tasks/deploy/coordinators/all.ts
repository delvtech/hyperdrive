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
  .addOptionalParam(
    "lido",
    "address of the lido contract",
    undefined,
    types.string,
  )
  .addOptionalParam(
    "reth",
    "address of the reth contract",
    undefined,
    types.string,
  )
  .addOptionalParam("admin", "admin address", undefined, types.string)
  .setAction(
    async (
      { admin }: DeployCoordinatorsAllParams,
      { run, config: hhConfig, network },
    ) => {
      const config = hhConfig.networks[network.name].coordinators;
      console.log("coordinator config", config);
      // deploy the erc4626 coordinator
      await run("deploy:coordinators:erc4626");
      // deploy the reth coordinator
      await run("deploy:coordinators:reth", {
        admin,
      } as DeployCoordinatorsRethParams);
      // deploy the steth coordinator
      await run("deploy:coordinators:steth", {
        admin,
      } as DeployCoordinatorsStethParams);
    },
  );
