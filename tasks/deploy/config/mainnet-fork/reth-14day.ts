import { formatEther, parseEther } from "viem";
import {
    HyperdriveInstanceConfig,
    RETH_ADDRESS_MAINNET,
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
import { MAINNET_FORK_RETH_COORDINATOR_NAME } from "./reth-coordinator";

export const MAINNET_FORK_RETH_14DAY_NAME = "RETH_14_DAY";
const CONTRIBUTION = parseEther("500");

export const MAINNET_FORK_RETH_14DAY: HyperdriveInstanceConfig<"RETH"> = {
    name: MAINNET_FORK_RETH_14DAY_NAME,
    prefix: "RETH",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(
            MAINNET_FORK_RETH_COORDINATOR_NAME,
        ).address,
    deploymentId: toBytes32(MAINNET_FORK_RETH_14DAY_NAME),
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
            RETH_ADDRESS_MAINNET,
        );
        let pc = await hre.viem.getPublicClient();
        let tx = await vaultSharesToken.write.approve([
            hre.hyperdriveDeploy.deployments.byName(
                MAINNET_FORK_RETH_COORDINATOR_NAME,
            ).address,
            CONTRIBUTION,
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
    },
    poolDeployConfig: async (hre) => {
        return {
            baseToken: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
            vaultSharesToken: RETH_ADDRESS_MAINNET,
            circuitBreakerDelta: parseEther("0.6"),
            minimumShareReserves: parseEther("0.001"),
            minimumTransactionAmount: parseEther("0.001"),
            positionDuration: parseDuration("14 days"),
            checkpointDuration: parseDuration("1 day"),
            timeStretch: 0n,
            governance: MAINNET_FORK_FACTORY_GOVERNANCE_ADDRESS,
            feeCollector: MAINNET_FORK_FACTORY_GOVERNANCE_ADDRESS,
            sweepCollector: MAINNET_FORK_FACTORY_GOVERNANCE_ADDRESS,
            ...(await getLinkerDetails(
                hre,
                hre.hyperdriveDeploy.deployments.byName(
                    MAINNET_FORK_FACTORY_NAME,
                ).address,
            )),
            checkpointRewarder: hre.hyperdriveDeploy.deployments.byName(
                MAINNET_FORK_CHECKPOINT_REWARDER_NAME,
            ).address,
            fees: {
                curve: parseEther("0.01"),
                flat: normalizeFee(parseEther("0.0005"), "14 days"),
                governanceLP: parseEther("0.15"),
                governanceZombie: parseEther("0.03"),
            },
        };
    },
};
