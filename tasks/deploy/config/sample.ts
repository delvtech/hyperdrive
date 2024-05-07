import { parseEther, toFunctionSelector } from "viem";
import {
    HyperdriveCoordinatorDeployConfigInput,
    HyperdriveDeployConfigInput,
    HyperdriveFactoryDeployConfigInput,
    HyperdriveInstanceDeployConfigInput,
} from "../schemas";

const SAMPLE_FACTORY: HyperdriveFactoryDeployConfigInput = {
    name: "SAMPLE_FACTORY",
    governance: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
    hyperdriveGovernance: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
    defaultPausers: ["0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8"],
    feeCollector: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
    sweepCollector: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
    checkpointDurationResolution: "8 hours",
    minCheckpointDuration: "24 hours",
    maxCheckpointDuration: "24 hours",
    minPositionDuration: "7 days",
    maxPositionDuration: "30 days",
    minFixedAPR: "0.01",
    maxFixedAPR: "0.6",
    minTimeStretchAPR: "0.01",
    maxTimeStretchAPR: "0.6",
    minCircuitBreakerDelta: "0.5",
    maxCircuitBreakerDelta: "1",
    minFees: {
        curve: "0.001",
        flat: "0.0001",
        governanceLP: "0.15",
        governanceZombie: "0.03",
    },
    maxFees: {
        curve: "0.1",
        flat: "0.1",
        governanceLP: "0.15",
        governanceZombie: "0.03",
    },
};

const SAMPLE_COORDINATOR: HyperdriveCoordinatorDeployConfigInput = {
    name: "SAMPLE_COORDINATOR",
    contract: "ERC4626HyperdriveDeployerCoordinator",
    factoryName: "SAMPLE_FACTORY",
    targetCount: 4,
    lpMath: "SAMPLE_LPMATH",
    setup: async (hre) => {
        // register the coordinator with the factory if the deployer is the governance address
        let deployer = (await hre.getNamedAccounts())["deployer"];
        let coordinatorDeployment = hre.hyperdriveDeploy.deployments.byName(
            "SAMPLE_COORDINATOR_ERC4626HyperdriveDeployerCoordinator",
            hre.network.name,
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
            !(await factory.read.isDeployerCoordinator([coordinator.address]))
        ) {
            console.log(
                `adding SAMPLE HyperdriveDeployerCoordinator to SAMPLE factory`,
            );
            let pc = await hre.viem.getPublicClient();
            let tx = await factory.write.addDeployerCoordinator([
                coordinator.address,
            ]);
            await pc.waitForTransactionReceipt({ hash: tx });
        }
    },
};

const SAMPLE_INSTANCE: HyperdriveInstanceDeployConfigInput = {
    name: "SAMPLE_INSTANCE",
    contract: "ERC4626Hyperdrive",
    coordinatorName: "SAMPLE_COORDINATOR_ERC4626HyperdriveDeployerCoordinator",
    deploymentId: "0x666",
    salt: "0x69420",
    contribution: "0.1",
    fixedAPR: "0.05",
    timestretchAPR: "0.05",
    options: {
        // destination: "0xsomeone",
        asBase: true,
        // extraData: "0x",
    },
    poolDeployConfig: {
        baseToken: {
            name: "SAMPLE_BASE",
            deploy: async (hre) => {
                let pc = await hre.viem.getPublicClient();
                let baseToken = await hre.hyperdriveDeploy.deployContract(
                    "SAMPLE_BASE",
                    "ERC20Mintable",
                    [
                        "DAI",
                        "DAI",
                        18,
                        "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
                        true,
                        parseEther("10000"),
                    ],
                    { noVerify: true },
                );
                // allow minting by the public
                let tx = await baseToken.write.setPublicCapability([
                    toFunctionSelector("mint(uint256)"),
                    true,
                ]);
                await pc.waitForTransactionReceipt({ hash: tx });
                tx = await baseToken.write.setPublicCapability([
                    toFunctionSelector("mint(address,uint256)"),
                    true,
                ]);
                await pc.waitForTransactionReceipt({ hash: tx });
                // approve the coordinator for the contribution
                tx = await baseToken.write.approve([
                    hre.hyperdriveDeploy.deployments.byName(
                        "SAMPLE_COORDINATOR_ERC4626HyperdriveDeployerCoordinator",
                        hre.network.name,
                    ).address,
                    parseEther("1000"),
                ]);
                tx = await baseToken.write.approve([
                    hre.hyperdriveDeploy.deployments.byName(
                        "SAMPLE_FACTORY",
                        hre.network.name,
                    ).address,
                    parseEther("1000"),
                ]);
                await pc.waitForTransactionReceipt({ hash: tx });
                await pc.waitForTransactionReceipt({ hash: tx });
                tx = await baseToken.write.mint([parseEther("0.1")]);
                await pc.waitForTransactionReceipt({ hash: tx });
            },
        },
        vaultSharesToken: {
            name: "SAMPLE_SHARES",
            deploy: async (hre) => {
                let pc = await hre.viem.getPublicClient();
                let baseToken = hre.hyperdriveDeploy.deployments.byName(
                    "SAMPLE_BASE",
                    hre.network.name,
                ).address;
                let vaultSharesToken =
                    await hre.hyperdriveDeploy.deployContract(
                        "SAMPLE_SHARES",
                        "MockERC4626",
                        [
                            baseToken,
                            "Savings DAI",
                            "SDAI",
                            parseEther("0.13"),
                            "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
                            true,
                            parseEther("10000"),
                        ],
                        { noVerify: true },
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
                // approve the coordinator for the contribution
                tx = await vaultSharesToken.write.approve([
                    hre.hyperdriveDeploy.deployments.byName(
                        "SAMPLE_COORDINATOR_ERC4626HyperdriveDeployerCoordinator",
                        hre.network.name,
                    ).address,
                    parseEther("1000"),
                ]);
                await pc.waitForTransactionReceipt({ hash: tx });
                tx = await vaultSharesToken.write.approve([
                    hre.hyperdriveDeploy.deployments.byName(
                        "SAMPLE_FACTORY",
                        hre.network.name,
                    ).address,
                    parseEther("1000"),
                ]);
                await pc.waitForTransactionReceipt({ hash: tx });
            },
        },
        circuitBreakerDelta: "0.6",
        minimumShareReserves: "0.01",
        minimumTransactionAmount: "0.001",
        positionDuration: "30 days",
        checkpointDuration: "1 day",
        timeStretch: "0",
        governance: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
        feeCollector: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
        sweepCollector: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
        fees: {
            curve: "0.05",
            flat: "0.05",
            governanceLP: "0.15",
            governanceZombie: "0.03",
        },
    },
};

// const SAMPLE_STETH: StETHInstanceDeployConfigInput = {
//     name: "SAMPLE_STETH",
//     deploymentId: "0x66666661",
//     salt: "0x6942011",
//     contribution: "0.01",
//     fixedAPR: "0.5",
//     timestretchAPR: "0.5",
//     options: {
//         // destination: "0xsomeone",
//         asBase: false,
//         // extraData: "0x",
//     },
//     poolDeployConfig: {
//         // vaultSharesToken: "0x...",
//         minimumShareReserves: "0.001",
//         minimumTransactionAmount: "0.001",
//         positionDuration: "30 days",
//         checkpointDuration: "1 day",
//         circuitBreakerDelta: "0.6",
//         timeStretch: "0",
//         governance: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
//         feeCollector: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
//         sweepCollector: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
//         fees: {
//             curve: "0.001",
//             flat: "0.0001",
//             governanceLP: "0.15",
//             governanceZombie: "0.03",
//         },
//     },
// };

// const SAMPLE_EZETH: EzETHInstanceDeployConfigInput = {
//     name: "SAMPLE_EZETH",
//     deploymentId: "0xabbabac",
//     salt: "0x69420",
//     contribution: "0.1",
//     fixedAPR: "0.5",
//     timestretchAPR: "0.5",
//     options: {
//         // destination: "0xsomeone",
//         asBase: false,
//         // extraData: "0x",
//     },
//     poolDeployConfig: {
//         // vaultSharesToken: "0x...",
//         minimumShareReserves: "0.001",
//         minimumTransactionAmount: "0.001",
//         positionDuration: "30 days",
//         checkpointDuration: "1 day",
//         circuitBreakerDelta: "0.6",
//         timeStretch: "0",
//         governance: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
//         feeCollector: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
//         sweepCollector: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
//         fees: {
//             curve: "0.001",
//             flat: "0.0001",
//             governanceLP: "0.15",
//             governanceZombie: "0.03",
//         },
//     },
// };

// const SAMPLE_RETH: RETHInstanceDeployConfigInput = {
//     name: "SAMPLE_RETH",
//     deploymentId: "0x665",
//     salt: "0x69420111232",
//     contribution: "0.01",
//     fixedAPR: "0.5",
//     timestretchAPR: "0.5",
//     options: {
//         // destination: "0xsomeone",
//         asBase: false,
//         // extraData: "0x",
//     },
//     poolDeployConfig: {
//         // vaultSharesToken: "0x...",
//         minimumShareReserves: "0.001",
//         minimumTransactionAmount: "0.001",
//         positionDuration: "30 days",
//         checkpointDuration: "1 day",
//         circuitBreakerDelta: "0.6",
//         timeStretch: "0",
//         governance: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
//         feeCollector: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
//         sweepCollector: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
//         fees: {
//             curve: "0.001",
//             flat: "0.0001",
//             governanceLP: "0.15",
//             governanceZombie: "0.03",
//         },
//     },
// };

export const SAMPLE_HYPERDRIVE: HyperdriveDeployConfigInput = {
    factories: [SAMPLE_FACTORY],
    coordinators: [SAMPLE_COORDINATOR],
    instances: [SAMPLE_INSTANCE],
};
