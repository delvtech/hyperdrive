import { formatEther, parseEther } from "viem";
import {
    HyperdriveInstanceConfig,
    MAINNET_RETH_ADDRESS,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";

const CONTRIBUTION = parseEther("500");

export const MAINNET_FORK_RETH_30DAY: HyperdriveInstanceConfig<"RETH"> = {
    name: "RETH_30_DAY",
    prefix: "RETH",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName("RETH_COORDINATOR").address,
    deploymentId: toBytes32("RETH_30_DAY"),
    salt: toBytes32("0x666"),
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
        await hre.run("fork:mint-reth", {
            address: (await hre.getNamedAccounts())["deployer"],
            amount: formatEther(CONTRIBUTION),
        });
        let vaultSharesToken = await hre.viem.getContractAt(
            "MockRocketPool",
            MAINNET_RETH_ADDRESS,
        );
        let pc = await hre.viem.getPublicClient();
        let tx = await vaultSharesToken.write.approve([
            hre.hyperdriveDeploy.deployments.byName("RETH_COORDINATOR").address,
            CONTRIBUTION,
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
    },
    poolDeployConfig: async (hre) => {
        return {
            baseToken: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
            vaultSharesToken: MAINNET_RETH_ADDRESS,
            circuitBreakerDelta: parseEther("0.6"),
            circuitBreakerAPR: parseEther("2"),
            minimumShareReserves: parseEther("0.001"),
            minimumTransactionAmount: parseEther("0.001"),
            positionDuration: parseDuration("30 days"),
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
                flat: normalizeFee(parseEther("0.0005"), "30 days"),
                governanceLP: parseEther("0.15"),
                governanceZombie: parseEther("0.03"),
            },
        };
    },
};
