import { Address, parseEther, toFunctionSelector } from "viem";
import { HyperdriveCoordinatorConfig } from "../../lib";
import { SEPOLIA_FACTORY_NAME } from "./factory";

export const SEPOLIA_RETH_COORDINATOR_NAME = "RETH_COORDINATOR";

export const SEPOLIA_RETH_COORDINATOR: HyperdriveCoordinatorConfig<"RETH"> = {
    name: SEPOLIA_RETH_COORDINATOR_NAME,
    prefix: "RETH",
    factoryAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(SEPOLIA_FACTORY_NAME).address,
    targetCount: 5,
    prepare: async (hre, options) => {
        let pc = await hre.viem.getPublicClient();
        let deployer = (await hre.getNamedAccounts())["deployer"] as Address;
        let vaultSharesToken = await hre.hyperdriveDeploy.ensureDeployed(
            "RETH",
            "MockRocketPool",
            [parseEther("0.035"), deployer, true, parseEther("500")],
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
        hre.hyperdriveDeploy.deployments.byName("RETH").address,
};
