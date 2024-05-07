import { parseEther, toFunctionSelector } from "viem";
import { HyperdriveCoordinatorDeployConfigInput } from "../../lib";

export const SEPOLIA_EZETH_COORDINATOR: HyperdriveCoordinatorDeployConfigInput =
    {
        name: "EZETH_COORDINATOR",
        contract: "EzETHHyperdriveDeployerCoordinator",
        factoryName: "FACTORY",
        targetCount: 4,
        lpMath: "SEPOLIA",
        coreConstructorArguments: async (hre) => [
            hre.hyperdriveDeploy.deployments.byName("EZETH").address,
        ],
        targetConstructorArguments: async (hre) => [
            hre.hyperdriveDeploy.deployments.byName("EZETH").address,
        ],
        token: {
            name: "EZETH",
            deploy: async (hre) => {
                let deployer = (await hre.getNamedAccounts())["deployer"];
                let pc = await hre.viem.getPublicClient();
                let vaultSharesToken =
                    await hre.hyperdriveDeploy.deployContract(
                        "EZETH",
                        "MockEzEthPool",
                        [
                            parseEther("0.035"),
                            "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
                            true,
                            parseEther("500"),
                        ],
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
                tx = await vaultSharesToken.write.submit(
                    [deployer as `0x${string}`],
                    {
                        value: parseEther("0.1"),
                    },
                );
                await pc.waitForTransactionReceipt({ hash: tx });
            },
        },
        setup: async (hre) => {
            // register the coordinator with the factory if the deployer is the governance address
            let deployer = (await hre.getNamedAccounts())["deployer"];
            let coordinatorDeployment =
                hre.hyperdriveDeploy.deployments.byName("EZETH_COORDINATOR");
            let coordinator = await hre.viem.getContractAt(
                "EzETHHyperdriveDeployerCoordinator",
                coordinatorDeployment.address,
            );
            let factory = await hre.viem.getContractAt(
                "HyperdriveFactory",
                await coordinator.read.factory(),
            );
            if (
                deployer === (await factory.read.governance()) &&
                !(await factory.read.isDeployerCoordinator([
                    coordinator.address,
                ]))
            ) {
                console.log(
                    `adding EzETHHyperdriveDeployerCoordinator to factory`,
                );
                let pc = await hre.viem.getPublicClient();
                let tx = await factory.write.addDeployerCoordinator([
                    coordinator.address,
                ]);
                await pc.waitForTransactionReceipt({ hash: tx });
            }
        },
    };
