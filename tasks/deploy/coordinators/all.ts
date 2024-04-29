import { task, types } from "hardhat/config";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
dayjs.extend(duration);

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
      { lido, reth, admin }: { lido?: string; reth?: string; admin?: string },
      { deployments, run, network, viem },
    ) => {
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
