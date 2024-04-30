import { task, types } from "hardhat/config";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { DeployFactoryParams } from "./factory";
import { DeployCoordinatorsAllParams } from "./coordinators";
import { DeployInstancesAllParams } from "./instances";
dayjs.extend(duration);

export type DeployAllParams = {} & DeployCoordinatorsAllParams;

task(
  "deploy:all",
  "deploys the HyperdriveFactory and all deployer coordinators",
)
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
    async ({ admin }: DeployAllParams, { run, network, config: hhConfig }) => {
      // deploy the forwarder
      await run("deploy:forwarder");

      // deploy the factory
      await run("deploy:factory");

      // deploy all deployer coordinators
      await run("deploy:coordinators:all", {
        admin,
      } as DeployCoordinatorsAllParams);

      // deploy all instances
      await run("deploy:instances:all", { admin } as DeployInstancesAllParams);
    },
  );
