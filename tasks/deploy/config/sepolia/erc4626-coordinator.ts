import { HyperdriveCoordinatorDeployConfigInput } from "../../lib";

export const SEPOLIA_ERC4626_COORDINATOR: HyperdriveCoordinatorDeployConfigInput =
    {
        name: "ERC4626_COORDINATOR",
        contract: "ERC4626HyperdriveDeployerCoordinator",
        factoryName: "FACTORY",
        targetCount: 4,
        lpMath: "SEPOLIA",
        setup: async (hre) => {
            // register the coordinator with the factory if the deployer is the governance address
            let deployer = (await hre.getNamedAccounts())["deployer"];
            let coordinatorDeployment = hre.hyperdriveDeploy.deployments.byName(
                "ERC4626_COORDINATOR",
            );
            let coordinator = await hre.viem.getContractAt(
                "ERC4626HyperdriveDeployerCoordinator",
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
                    `adding ERC4626HyperdriveDeployerCoordinator to factory`,
                );
                let pc = await hre.viem.getPublicClient();
                let tx = await factory.write.addDeployerCoordinator([
                    coordinator.address,
                ]);
                await pc.waitForTransactionReceipt({ hash: tx });
            }
        },
    };
