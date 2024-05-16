import { parseEther } from "viem";
import {
    HyperdriveInstanceDeployConfigInput,
    toBytes32,
} from "../../lib";

const CONTRIBUTION = "500";

export const SEPOLIA_RETH_14DAY: HyperdriveInstanceDeployConfigInput = {
    name: "RETH_14_DAY",
    contract: "RETHHyperdrive",
    coordinatorName: "RETH_COORDINATOR",
    deploymentId: toBytes32("RETH_14_DAY"),
    salt: "0x80085",
    contribution: CONTRIBUTION,
    fixedAPR: "0.05",
    timestretchAPR: "0.05",
    options: {
        // destination: "0xsomeone", defaults to deployer
        asBase: false,
        // extraData: "0x",
    },
    poolDeployConfig: {
        baseToken: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
        vaultSharesToken: {
            name: "RETH",
            deploy: async (hre) => {
                let vaultSharesToken = await hre.viem.getContractAt(
                    "MockRocketPool",
                    hre.hyperdriveDeploy.deployments.byName("RETH").address,
                );
                let pc = await hre.viem.getPublicClient();
                // mint the contribution
                let tx = await vaultSharesToken.write.mint([
                    parseEther(CONTRIBUTION),
                ]);
                // approve the coordinator
                tx = await vaultSharesToken.write.approve([
                    hre.hyperdriveDeploy.deployments.byName("RETH_COORDINATOR")
                        .address,
                    parseEther(CONTRIBUTION) + parseEther("10"),
                ]);
                await pc.waitForTransactionReceipt({ hash: tx });
            },
        },
        circuitBreakerDelta: "0.6",
        minimumShareReserves: "0.001",
        minimumTransactionAmount: "0.001",
        positionDuration: "14 days",
        checkpointDuration: "1 day",
        timeStretch: "0",
        governance: "0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b",
        feeCollector: "0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b",
        sweepCollector: "0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b",
        fees: {
            curve: "0.01",
            flat: "0.0005",
            governanceLP: "0.15",
            governanceZombie: "0.03",
        },
    },
};
