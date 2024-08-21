import { Address, parseEther } from "viem";
import {
    HyperdriveInstanceConfig,
    TWO_WEEKS,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";
import { SEPOLIA_CHECKPOINT_REWARDER_NAME } from "./checkpoint-rewarder";
import { SEPOLIA_EETH_COORDINATOR_NAME } from "./eeth-coordinator";
import {
    SEPOLIA_FACTORY_GOVERNANCE_ADDRESS,
    SEPOLIA_FACTORY_NAME,
} from "./factory";

export const SEPOLIA_EETH_14DAY_NAME = "EETH_14_DAY";

const CONTRIBUTION = parseEther("500");

export const SEPOLIA_EETH_14DAY: HyperdriveInstanceConfig<"EETH"> = {
    name: SEPOLIA_EETH_14DAY_NAME,
    prefix: "EETH",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(SEPOLIA_EETH_COORDINATOR_NAME)
            .address,
    deploymentId: toBytes32(SEPOLIA_EETH_14DAY_NAME),
    salt: toBytes32("0xababe123"),
    extraData: "0x",
    contribution: CONTRIBUTION,
    fixedAPR: parseEther("0.03"),
    timestretchAPR: parseEther("0.03"),
    options: async (hre) => ({
        extraData: "0x",
        asBase: false,
        destination: (await hre.getNamedAccounts())["deployer"] as Address,
    }),
    prepare: async (hre, options) => {
        let vaultSharesToken = await hre.hyperdriveDeploy.ensureDeployed(
            "EETH",
            "MockEETH",
            [
                parseEther("0.03"),
                (await hre.getNamedAccounts())["deployer"] as Address,
                true,
                parseEther("10000"),
            ],
            options,
        );
        let pc = await hre.viem.getPublicClient();
        // mint the contribution
        let tx = await vaultSharesToken.write.mint([CONTRIBUTION]);
        await pc.waitForTransactionReceipt({ hash: tx });
        // approve the coordinator
        tx = await vaultSharesToken.write.approve([
            hre.hyperdriveDeploy.deployments.byName(
                SEPOLIA_EETH_COORDINATOR_NAME,
            ).address,
            await vaultSharesToken.read.getPooledEthByShares([CONTRIBUTION]),
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
    },
    poolDeployConfig: async (hre) => {
        return {
            baseToken: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
            vaultSharesToken:
                hre.hyperdriveDeploy.deployments.byName("EETH").address,
            circuitBreakerDelta: parseEther("0.5"),
            minimumShareReserves: parseEther("0.001"),
            minimumTransactionAmount: parseEther("0.001"),
            positionDuration: parseDuration(TWO_WEEKS),
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
                flat: normalizeFee(parseEther("0.0005"), TWO_WEEKS),
                governanceLP: parseEther("0.15"),
                governanceZombie: parseEther("0.03"),
            },
        };
    },
};
