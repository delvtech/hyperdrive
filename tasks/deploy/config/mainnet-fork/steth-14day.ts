import { formatEther, parseEther } from "viem";
import {
    HyperdriveInstanceConfig,
    MAINNET_STETH_ADDRESS,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";
import { MAINNET_FORK_CHECKPOINT_REWARDER_NAME } from "./checkpoint-rewarder";
import {
    MAINNET_FORK_FACTORY_GOVERNANCE_ADDRESS,
    MAINNET_FORK_FACTORY_NAME,
} from "./factory";
import { MAINNET_FORK_STETH_COORDINATOR_NAME } from "./steth-coordinator";

export const MAINNET_FORK_STETH_14DAY_NAME = "STETH_14_DAY";
const CONTRIBUTION = parseEther("500");

export const MAINNET_FORK_STETH_14DAY: HyperdriveInstanceConfig<"StETH"> = {
    name: MAINNET_FORK_STETH_14DAY_NAME,
    prefix: "StETH",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(
            MAINNET_FORK_STETH_COORDINATOR_NAME,
        ).address,
    deploymentId: toBytes32(MAINNET_FORK_STETH_14DAY_NAME),
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
        let vaultSharesToken = await hre.viem.getContractAt(
            "MockLido",
            MAINNET_STETH_ADDRESS,
        );
        let pc = await hre.viem.getPublicClient();
        // approve the coordinator
        let tx = await vaultSharesToken.write.approve([
            hre.hyperdriveDeploy.deployments.byName(
                MAINNET_FORK_STETH_COORDINATOR_NAME,
            ).address,
            await vaultSharesToken.read.getPooledEthByShares([CONTRIBUTION]),
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
        // mint steth
        await hre.run("fork:mint-steth", {
            amount: formatEther(CONTRIBUTION),
            address: (await hre.getNamedAccounts())["deployer"],
        });
    },
    poolDeployConfig: async (hre) => {
        return {
            baseToken: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
            vaultSharesToken: MAINNET_STETH_ADDRESS,
            circuitBreakerDelta: parseEther("0.6"),
            minimumShareReserves: parseEther("0.001"),
            minimumTransactionAmount: parseEther("0.001"),
            positionDuration: parseDuration("14 days"),
            checkpointDuration: parseDuration("1 day"),
            timeStretch: 0n,
            governance: MAINNET_FORK_FACTORY_GOVERNANCE_ADDRESS,
            feeCollector: MAINNET_FORK_FACTORY_GOVERNANCE_ADDRESS,
            sweepCollector: MAINNET_FORK_FACTORY_GOVERNANCE_ADDRESS,
            checkpointRewarder: hre.hyperdriveDeploy.deployments.byName(
                MAINNET_FORK_CHECKPOINT_REWARDER_NAME,
            ).address,
            ...(await getLinkerDetails(
                hre,
                hre.hyperdriveDeploy.deployments.byName(
                    MAINNET_FORK_FACTORY_NAME,
                ).address,
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
