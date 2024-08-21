import { Address, parseEther, toFunctionSelector } from "viem";
import { HyperdriveCoordinatorConfig } from "../../lib";
import { SEPOLIA_FACTORY_NAME } from "./factory";

export const SEPOLIA_EETH_COORDINATOR_NAME = "EETH_COORDINATOR";

export const SEPOLIA_EETH_COORDINATOR: HyperdriveCoordinatorConfig<"EETH"> = {
    name: SEPOLIA_EETH_COORDINATOR_NAME,
    prefix: "EETH",
    targetCount: 5,
    factoryAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(SEPOLIA_FACTORY_NAME).address,
    extraConstructorArgs: async (hre) => [
        hre.hyperdriveDeploy.deployments.byName("EETH").address,
    ],
    prepare: async (hre, options) => {
        let deployer = (await hre.getNamedAccounts())["deployer"] as Address;
        let pc = await hre.viem.getPublicClient();
        let vaultSharesToken = await hre.hyperdriveDeploy.ensureDeployed(
            "EETH",
            "MockEETH",
            [
                parseEther("0.03"),
                (await hre.getNamedAccounts())["deployer"] as Address,
                true,
                parseEther("10000"),
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
        hre.hyperdriveDeploy.deployments.byName("EETH").address,
};
