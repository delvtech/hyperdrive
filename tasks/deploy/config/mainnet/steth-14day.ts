import { parseEther } from "viem";
import {
    HyperdriveInstanceConfig,
    MAINNET_STETH_ADDRESS,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";

// FIXME: Use a smaller contribution.
const CONTRIBUTION = parseEther("500");

// FIXME: What will the name of this be.
export const MAINNET_STETH_14DAY: HyperdriveInstanceConfig<"StETH"> = {
    name: "STETH_14_DAY",
    prefix: "StETH",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName("STETH_COORDINATOR").address,
    deploymentId: toBytes32("STETH_14_DAY"),
    salt: toBytes32("0xababe"),
    extraData: "0x",
    contribution: CONTRIBUTION,
    fixedAPR: parseEther("0.05"),
    timestretchAPR: parseEther("0.05"),
    options: {
        destination: process.env.ADMIN! as `0x${string}`,
        asBase: false,
        extraData: "0x",
    },
    prepare: async (hre) => {
        // FIXME: Why can't we use ILido?
        // approve the coordinator
        let vaultSharesToken = await hre.viem.getContractAt(
            "MockLido",
            MAINNET_STETH_ADDRESS,
        );
        let pc = await hre.viem.getPublicClient();
        let tx = await vaultSharesToken.write.approve([
            hre.hyperdriveDeploy.deployments.byName("STETH_COORDINATOR")
                .address,
            await vaultSharesToken.read.getPooledEthByShares([CONTRIBUTION]),
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
    },
    poolDeployConfig: async (hre) => {
        // FIXME: Update this configuration
        return {
            baseToken: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
            vaultSharesToken: MAINNET_STETH_ADDRESS,
            circuitBreakerDelta: parseEther("0.6"),
            minimumShareReserves: parseEther("0.001"),
            minimumTransactionAmount: parseEther("0.001"),
            positionDuration: parseDuration("14 days"),
            checkpointDuration: parseDuration("1 day"),
            timeStretch: 0n,
            governance: "0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b",
            feeCollector: "0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b",
            sweepCollector: "0xc187a246Ee5A4Fe4395a8f6C0f9F2AA3A5a06e9b",
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
