import { parseEther } from "viem";
import {
    HyperdriveInstanceConfig,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";

const CONTRIBUTION = parseEther("500");

export const SEPOLIA_EZETH_14DAY: HyperdriveInstanceConfig<"EzETH"> = {
    name: "EZETH_14_DAY",
    prefix: "EzETH",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName("EZETH_COORDINATOR").address,
    deploymentId: toBytes32("EZETH_14_DAY"),
    salt: toBytes32("0xababe"),
    extraData: "0x",
    contribution: CONTRIBUTION,
    fixedAPR: parseEther("0.05"),
    timestretchAPR: parseEther("0.05"),
    options: {
        destination: "0xd94a3A0BfC798b98a700a785D5C610E8a2d5DBD8",
        asBase: false,
        extraData: "0x",
    },
    prepare: async (hre) => {
        let vaultSharesToken = await hre.viem.getContractAt(
            "MockEzEthPool",
            hre.hyperdriveDeploy.deployments.byName("EZETH").address,
        );
        let pc = await hre.viem.getPublicClient();
        // mint the contribution
        let tx = await vaultSharesToken.write.mint([CONTRIBUTION]);
        await pc.waitForTransactionReceipt({ hash: tx });
        // approve the coordinator
        tx = await vaultSharesToken.write.approve([
            hre.hyperdriveDeploy.deployments.byName("EZETH_COORDINATOR")
                .address,
            CONTRIBUTION + parseEther("0.01"),
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
    },
    poolDeployConfig: async (hre) => {
        return {
            baseToken: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
            vaultSharesToken:
                hre.hyperdriveDeploy.deployments.byName("EZETH").address,
            circuitBreakerDelta: parseEther("0.6"),
            minimumShareReserves: parseEther("0.001"),
            minimumTransactionAmount: parseEther("0.001"),
            positionDuration: parseDuration("14 days"),
            checkpointDuration: parseDuration("1 day"),
            timeStretch: 0n,
            governance: "0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b",
            feeCollector: "0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b",
            sweepCollector: "0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b",
            checkpointRewarder: hre.hyperdriveDeploy.deployments.byName(
                "CHECKPOINT_REWARDER",
            ).address,
            ...(await getLinkerDetails(
                hre,
                hre.hyperdriveDeploy.deployments.byName("FACTORY").address,
            )),
            fees: {
                curve: parseEther("0.01"),
                flat: normalizeFee(parseEther("0.0005"), "14 days"),
                governanceLP: parseEther("0.15"),
                governanceZombie: parseEther("0.03"),
            },
        };
    },
};
