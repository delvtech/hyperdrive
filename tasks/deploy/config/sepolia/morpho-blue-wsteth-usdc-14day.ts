import { Address, encodeAbiParameters, parseEther, zeroAddress } from "viem";
import {
    HyperdriveInstanceConfig,
    TWO_WEEKS,
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

export const SEPOLIA_MORPHO_BLUE_WSTETH_USDC_14DAY_NAME =
    "ElementDAO 14 Day wstETH/USDC Morpho Blue Hyperdrive";

const CONTRIBUTION = 100_000_000n;

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
            morpho: "0x927A9E3C4B897eF5135e6B2C7689637fA8E2E0Bd" as Address,
            collateralToken:
                "0xB82381A3fBD3FaFA77B3a7bE693342618240067b" as Address, // Sepolia wstETH
            oracle: "0x8f1AE6B11a339e829243fe0404b9496631E2AC64" as Address,
            irm: "0x0fB591F09ab2eB967c0EFB9eE0EF6642c2abe6Ab" as Address,
            lltv: BigInt("860000000000000000"),
        },
    ],
);

export const SEPOLIA_MORPHO_BLUE_WSTETH_USDC_14DAY: HyperdriveInstanceConfig<"MorphoBlue"> =
    {
        name: SEPOLIA_MORPHO_BLUE_WSTETH_USDC_14DAY_NAME,
        prefix: "MorphoBlue",
        coordinatorAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName(
                SEPOLIA_MORPHO_BLUE_COORDINATOR_NAME,
            ).address,
        deploymentId: toBytes32(
            SEPOLIA_MORPHO_BLUE_WSTETH_USDC_14DAY_NAME.slice(0, 32),
        ),
        salt: toBytes32("0x420123456"),
        extraData: enc,
        contribution: CONTRIBUTION,
        fixedAPR: parseEther("0.1"),
        timestretchAPR: parseEther("0.1"),
        options: async (hre) => ({
            extraData: "0x",
            asBase: true,
            destination: (await hre.getNamedAccounts())["deployer"] as Address,
        }),
        prepare: async (hre, options) => {
            let pc = await hre.viem.getPublicClient();
            let baseToken = await hre.hyperdriveDeploy.ensureDeployed(
                "USDC",
                "ERC20Mintable",
                [
                    "USDC",
                    "USDC",
                    6,
                    (await hre.getNamedAccounts())["deployer"] as Address,
                    true,
                    1000_000_000n,
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
                    hre.hyperdriveDeploy.deployments.byName("USDC").address,
                vaultSharesToken: zeroAddress,
                circuitBreakerDelta: parseEther("0.5"),
                minimumShareReserves: 1_000_00n,
                minimumTransactionAmount: 1_000_000n,
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
                    hre.hyperdriveDeploy.deployments.byName(
                        SEPOLIA_FACTORY_NAME,
                    ).address,
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