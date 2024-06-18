import { Address, parseEther } from "viem";
import {
    HyperdriveInstanceConfig,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";
import { SEPOLIA_CHECKPOINT_REWARDER_NAME } from "./checkpoint-rewarder";
import {
    SEPOLIA_FACTORY_GOVERNANCE_ADDRESS,
    SEPOLIA_FACTORY_NAME,
} from "./factory";
import { SEPOLIA_RETH_COORDINATOR_NAME } from "./reth-coordinator";

export const SEPOLIA_RETH_30DAY_NAME = "RETH_30_DAY";
const CONTRIBUTION = parseEther("500");

export const SEPOLIA_RETH_30DAY: HyperdriveInstanceConfig<"RETH"> = {
    name: SEPOLIA_RETH_30DAY_NAME,
    prefix: "RETH",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(SEPOLIA_RETH_COORDINATOR_NAME)
            .address,
    deploymentId: toBytes32(SEPOLIA_RETH_30DAY_NAME),
    salt: toBytes32("0x666"),
    extraData: "0x",
    contribution: CONTRIBUTION,
    fixedAPR: parseEther("0.05"),
    timestretchAPR: parseEther("0.05"),
    options: async (hre) => ({
        extraData: "0x",
        asBase: false,
        destination: (await hre.getNamedAccounts())["deployer"] as Address,
    }),
    prepare: async (hre) => {
        let vaultSharesToken = await hre.viem.getContractAt(
            "MockRocketPool",
            hre.hyperdriveDeploy.deployments.byName("RETH").address,
        );
        let pc = await hre.viem.getPublicClient();
        // mint the contribution
        let tx = await vaultSharesToken.write.mint([CONTRIBUTION]);
        await pc.waitForTransactionReceipt({ hash: tx });
        // approve the coordinator
        tx = await vaultSharesToken.write.approve([
            hre.hyperdriveDeploy.deployments.byName("RETH_COORDINATOR").address,
            CONTRIBUTION,
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
    },
    poolDeployConfig: async (hre) => {
        return {
            baseToken: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
            vaultSharesToken:
                hre.hyperdriveDeploy.deployments.byName("RETH").address,
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
