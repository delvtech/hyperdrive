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
import { SEPOLIA_ERC4626_COORDINATOR_NAME } from "./erc4626-coordinator";
import {
    SEPOLIA_FACTORY_GOVERNANCE_ADDRESS,
    SEPOLIA_FACTORY_NAME,
} from "./factory";

export const SEPOLIA_MORPHO_DAI_14DAY_NAME = "MORPHO_DAI_14_DAY";

const CONTRIBUTION = parseEther("10000");

export const SEPOLIA_MORPHO_DAI_14DAY: HyperdriveInstanceConfig<"ERC4626"> = {
    name: SEPOLIA_MORPHO_DAI_14DAY_NAME,
    prefix: "ERC4626",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(
            SEPOLIA_ERC4626_COORDINATOR_NAME,
        ).address,
    deploymentId: toBytes32(SEPOLIA_MORPHO_DAI_14DAY_NAME),
    salt: toBytes32("0x69420"),
    extraData: "0x",
    contribution: CONTRIBUTION,
    fixedAPR: parseEther("0.10"),
    timestretchAPR: parseEther("0.10"),
    options: async (hre) => ({
        extraData: "0x",
        asBase: true,
        destination: (await hre.getNamedAccounts())["deployer"] as Address,
    }),
    prepare: async (hre, options) => {
        let pc = await hre.viem.getPublicClient();
        let baseToken = await hre.hyperdriveDeploy.ensureDeployed(
            "DAI",
            "ERC20Mintable",
            [
                "DAI",
                "DAI",
                18,
                (await hre.getNamedAccounts())["deployer"] as Address,
                true,
                parseEther("10000"),
            ],
            options,
        );

        // approve the coordinator for the contribution
        let tx = await baseToken.write.approve([
            hre.hyperdriveDeploy.deployments.byName(
                SEPOLIA_ERC4626_COORDINATOR_NAME,
            ).address,
            CONTRIBUTION,
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });

        // mint some tokens for the contribution
        tx = await baseToken.write.mint([CONTRIBUTION]);
        await pc.waitForTransactionReceipt({ hash: tx });
    },
    poolDeployConfig: async (hre) => {
        return {
            baseToken: hre.hyperdriveDeploy.deployments.byName("DAI").address,
            vaultSharesToken: "0x80191B6a6A8E2026209fB5d1e4e9CC9A73029511",
            circuitBreakerDelta: parseEther("0.6"),
            minimumShareReserves: parseEther("10"),
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
