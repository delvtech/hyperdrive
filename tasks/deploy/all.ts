import { task, types } from "hardhat/config";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
dayjs.extend(duration);

task(
  "deploy:all",
  "deploys the HyperdriveFactory and all deployer coordinators",
)
  .addParam(
    "configFile",
    "factory configuration file",
    undefined,
    types.inputFile,
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
    async (
      {
        configFile,
        lido,
        reth,
        admin,
      }: { configFile: string; lido?: string; reth?: string; admin?: string },
      { run },
    ) => {
      // deploy the factory
      await run("deploy:factory", {
        configFile,
      });
      // deploy the erc4626 coordinator
      await run("deploy:coordinators:erc4626");
      // deploy the reth coordinator
      await run("deploy:coordinators:reth", {
        admin,
        reth,
      });
      // deploy the steth coordinator
      await run("deploy:coordinators:steth", {
        admin,
        lido,
      });
    },
  );
