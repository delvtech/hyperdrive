import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { task, types } from "hardhat/config";

dayjs.extend(duration);

export type DeployInstancesAllParams = {
  admin?: string;
};

task("deploy:instances:all", "deploys all hyperdrive instances")
  .addOptionalParam("admin", "admin address", undefined, types.string)
  .setAction(
    async (
      { admin }: DeployInstancesAllParams,
      { run, network, config: hardhatConfig },
    ) => {
      // Read the instance configurations from hardhat config
      const instances = hardhatConfig.networks[network.name].instances;
      if (!instances) {
        console.error("no instances to deploy");
        return;
      }
      const { erc4626, steth, reth } = instances;

      if (erc4626) {
        for (let { name } of erc4626) {
          await run("deploy:instances:erc4626", { name, admin });
        }
      }

      if (steth) {
        for (let { name } of steth) {
          await run("deploy:instances:steth", { name, admin });
        }
      }

      if (reth) {
        for (let { name } of reth) {
          await run("deploy:instances:reth", { name, admin });
        }
      }
    },
  );
