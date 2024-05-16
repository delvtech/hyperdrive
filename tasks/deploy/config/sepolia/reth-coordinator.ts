import { parseEther, toFunctionSelector } from "viem";
import { HyperdriveCoordinatorConfig } from "../../lib";

export const SEPOLIA_RETH_COORDINATOR: HyperdriveCoordinatorConfig<"RETH"> = {
    name: "RETH_COORDINATOR",
    prefix: "RETH",
    factoryAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName("FACTORY").address,
    targetCount: 4,
    extraConstructorArgs: [],
    token: async (hre, options) => {
        let pc = await hre.viem.getPublicClient();
        let deployer = (await hre.getNamedAccounts())["deployer"];
        let vaultSharesToken = await hre.hyperdriveDeploy.ensureDeployed(
            "RETH",
            "MockRocketPool",
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
        return vaultSharesToken.address;
    },
};
