import { task, types } from "hardhat/config";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";

dayjs.extend(duration);

export type DeployInstancesAllParams = {
  admin?: string;
};

task("deploy:instances:all", "deploys all hyperdrive instances")
  .addOptionalParam("admin", "admin address", undefined, types.string)
  .setAction(
    async (
      { admin }: DeployInstancesAllParams,
      {
        deployments,
        run,
        network,
        viem,
        getNamedAccounts,
        config: hardhatConfig,
      },
    ) => {
      const erc4626 = hardhatConfig.networks[network.name].instances?.erc4626;
      console.log("erc4626 instances", erc4626);
      if (erc4626) {
        for (let { name } of erc4626) {
          await run("deploy:instances:erc4626", { name, admin });
        }
      }
    },
  );
