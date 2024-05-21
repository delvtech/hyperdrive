import { Address, maxUint256, parseEther, toFunctionSelector } from "viem";
import { HyperdriveCoordinatorConfig } from "../../lib";

let { env } = process;

export const ANVIL_STETH_COORDINATOR: HyperdriveCoordinatorConfig<"StETH"> = {
    name: "STETH_COORDINATOR",
    prefix: "StETH",
    factoryAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName("FACTORY").address,
    targetCount: 4,
    prepare: async (hre, options) => {
        let deployer = (await hre.getNamedAccounts())["deployer"];
        let pc = await hre.viem.getPublicClient();
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
        // allow minting by the public
        let tx = await vaultSharesToken.write.setPublicCapability([
            toFunctionSelector("mint(uint256)"),
            true,
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
        tx = await vaultSharesToken.write.setPublicCapability([
            toFunctionSelector("mint(address,uint256)"),
            true,
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
        // submit to initialize pool assets
        tx = await vaultSharesToken.write.submit([deployer as `0x${string}`], {
            value: parseEther("1"),
        });
        await pc.waitForTransactionReceipt({ hash: tx });
    },
    token: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName("STETH").address,
};
