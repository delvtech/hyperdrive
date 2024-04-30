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
          console.log(`deploying erc4626 instance ${name}`);
          await run("deploy:instances:erc4626", { name, admin });
        }
      }

      if (steth) {
        for (let { name } of steth) {
          console.log(`deploying steth instance ${name}`);
          await run("deploy:instances:steth", { name, admin });
        }
      }

      if (reth) {
        for (let { name } of reth) {
          console.log(`deploying reth instance ${name}`);
          await run("deploy:instances:reth", { name, admin });
        }
      }
    },
  );
