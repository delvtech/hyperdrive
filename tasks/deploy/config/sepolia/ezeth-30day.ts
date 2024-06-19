import { Address, parseEther } from "viem";
import {
    HyperdriveInstanceConfig,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";
import { SEPOLIA_CHECKPOINT_REWARDER_NAME } from "./checkpoint-rewarder";
import { SEPOLIA_EZETH_COORDINATOR_NAME } from "./ezeth-coordinator";
import {
    SEPOLIA_FACTORY_GOVERNANCE_ADDRESS,
    SEPOLIA_FACTORY_NAME,
} from "./factory";

export const SEPOLIA_EZETH_30DAY_NAME = "EZETH_30_DAY";

const CONTRIBUTION = parseEther("500");

export const SEPOLIA_EZETH_30DAY: HyperdriveInstanceConfig<"EzETH"> = {
    name: SEPOLIA_EZETH_30DAY_NAME,
    prefix: "EzETH",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(SEPOLIA_EZETH_COORDINATOR_NAME)
            .address,
    deploymentId: toBytes32(SEPOLIA_EZETH_30DAY_NAME),
    salt: toBytes32("0xababe"),
    extraData: "0x",
    contribution: CONTRIBUTION,
    fixedAPR: parseEther("0.05"),
    timestretchAPR: parseEther("0.05"),
    options: async (hre) => ({
        destination: (await hre.getNamedAccounts())["deployer"] as Address,
        asBase: false,
        extraData: "0x",
    }),
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
            hre.hyperdriveDeploy.deployments.byName(
                SEPOLIA_EZETH_COORDINATOR_NAME,
            ).address,
            CONTRIBUTION,
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
            positionDuration: parseDuration("30 days"),
            checkpointDuration: parseDuration("1 day"),
            timeStretch: 0n,
            governance: SEPOLIA_FACTORY_GOVERNANCE_ADDRESS,
            feeCollector: SEPOLIA_FACTORY_GOVERNANCE_ADDRESS,
            sweepCollector: SEPOLIA_FACTORY_GOVERNANCE_ADDRESS,
            checkpointRewarder: hre.hyperdriveDeploy.deployments.byName(
                SEPOLIA_CHECKPOINT_REWARDER_NAME,
            ).address,
            ...(await getLinkerDetails(
                hre,
                hre.hyperdriveDeploy.deployments.byName(SEPOLIA_FACTORY_NAME)
                    .address,
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
