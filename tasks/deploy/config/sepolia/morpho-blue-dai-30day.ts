import { Address, encodeAbiParameters, parseEther, zeroAddress } from "viem";
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
import { SEPOLIA_MORPHO_BLUE_COORDINATOR_NAME } from "./morpho-blue-coordinator";

export const SEPOLIA_MORPHO_BLUE_DAI_30DAY_NAME = "MORPHO_BLUE_DAI_30_DAY";

const CONTRIBUTION = parseEther("10000");

const enc = encodeAbiParameters(
    [
        {
            components: [
                {
                    name: "morpho",
                    type: "address",
                },
                {
                    name: "collateralToken",
                    type: "address",
                },
                {
                    name: "oracle",
                    type: "address",
                },
                {
                    name: "irm",
                    type: "address",
                },
                {
                    name: "lltv",
                    type: "uint256",
                },
            ],
            name: "MorphoBlueParams",
            type: "tuple",
        },
    ],
    [
        {
            morpho: "0x927A9E3C4B897eF5135e6B2C7689637fA8E2E0Bd" as `0x${string}`,
            collateralToken:
                "0xFF8AFe6bb92eB9D8e80c607bbe5bbb78BF1201Df" as `0x${string}`, // Hyperdrive Sepolia sDAI
            oracle: "0x23F3A48121861b78f66BbE3DF60AD24A21c4DDad" as `0x${string}`,
            irm: "0x0fB591F09ab2eB967c0EFB9eE0EF6642c2abe6Ab" as `0x${string}`,
            lltv: BigInt("980000000000000000"),
        },
    ],
);

export const SEPOLIA_MORPHO_BLUE_DAI_30DAY: HyperdriveInstanceConfig<"MorphoBlue"> =
    {
        name: SEPOLIA_MORPHO_BLUE_DAI_30DAY_NAME,
        prefix: "MorphoBlue",
        coordinatorAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName(
                SEPOLIA_MORPHO_BLUE_COORDINATOR_NAME,
            ).address,
        deploymentId: toBytes32(SEPOLIA_MORPHO_BLUE_DAI_30DAY_NAME),
        salt: toBytes32("0x0707"),
        extraData: enc,
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
                    SEPOLIA_MORPHO_BLUE_COORDINATOR_NAME,
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
                baseToken:
                    hre.hyperdriveDeploy.deployments.byName("DAI").address,
                vaultSharesToken: zeroAddress,
                circuitBreakerDelta: parseEther("0.6"),
                minimumShareReserves: parseEther("10"),
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
                    hre.hyperdriveDeploy.deployments.byName(
                        SEPOLIA_FACTORY_NAME,
                    ).address,
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
