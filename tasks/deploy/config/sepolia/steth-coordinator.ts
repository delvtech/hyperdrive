import { parseEther, toFunctionSelector } from "viem";
import { HyperdriveCoordinatorConfig } from "../../lib";
import { SEPOLIA_FACTORY_NAME } from "./factory";

export const SEPOLIA_STETH_COORDINATOR_NAME = "STETH_COORDINATOR";

export const SEPOLIA_STETH_COORDINATOR: HyperdriveCoordinatorConfig<"StETH"> = {
    name: "STETH_COORDINATOR",
    prefix: "StETH",
    factoryAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(SEPOLIA_FACTORY_NAME).address,
    targetCount: 5,
    prepare: async (hre, options) => {
        let deployer = (await hre.getNamedAccounts())["deployer"];
        let pc = await hre.viem.getPublicClient();
        let vaultSharesToken = await hre.hyperdriveDeploy.ensureDeployed(
            "STETH",
            "MockLido",
            [
                parseEther("0.035"),
                "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
                true,
                parseEther("500"),
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
            value: parseEther("0.1"),
        });
        await pc.waitForTransactionReceipt({ hash: tx });
    },
    token: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName("STETH").address,
};
