import { Address, maxUint256, parseEther, zeroAddress } from "viem";
import { HyperdriveCoordinatorConfig } from "../../lib";
import { ANVIL_FACTORY_NAME } from "./factory";

let { env } = process;

export const ANVIL_STETH_COORDINATOR: HyperdriveCoordinatorConfig<"StETH"> = {
    name: "STETH_COORDINATOR",
    prefix: "StETH",
    factoryAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(ANVIL_FACTORY_NAME).address,
    targetCount: 5,
    // Prepare for deploying the coordinator by ensuring the StETH token
    // is deployed, initialized with an ETH balance, and that ownership is
    // transferred to the admin address.
    prepare: async (hre, options) => {
        let deployer = (await hre.getNamedAccounts())["deployer"];
        let pc = await hre.viem.getPublicClient();
        let tc = await hre.viem.getTestClient({
            mode: "anvil",
        });
        let vaultSharesToken = await hre.hyperdriveDeploy.ensureDeployed(
            "STETH",
            "MockLido",
            [
                parseEther(env.LIDO_STARTING_RATE!),
                env.ADMIN! as Address,
                env.IS_COMPETITION_MODE! === "true",
                maxUint256,
            ],
            options,
        );
        await tc.setBalance({
            address: deployer as Address,
            value:
                (await pc.getBalance({ address: deployer as Address })) +
                parseEther("1"),
        });
        let tx = await vaultSharesToken.write.submit([zeroAddress], {
            value: parseEther("1"),
        });
        await pc.waitForTransactionReceipt({ hash: tx });
        tx = await vaultSharesToken.write.transferOwnership([
            env.ADMIN! as Address,
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
    },
    token: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName("STETH").address,
};
