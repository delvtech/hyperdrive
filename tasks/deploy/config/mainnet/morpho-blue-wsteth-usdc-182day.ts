import {
    Address,
    encodeAbiParameters,
    keccak256,
    parseEther,
    toHex,
    zeroAddress,
} from "viem";
import {
    HyperdriveInstanceConfig,
    SIX_MONTHS,
    USDC_ADDRESS_MAINNET,
    WSTETH_ADDRESS_MAINNET,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";
import { MAINNET_FACTORY_NAME } from "./factory";
import { MAINNET_MORPHO_BLUE_COORDINATOR_NAME } from "./morpho-blue-coordinator";

export const MAINNET_MORPHO_BLUE_WSTETH_USDC_182DAY_NAME =
    "ElementDAO 182 Day Morpho Blue wstETH/USDC Hyperdrive";

// USDC only has 6 decimals.
const CONTRIBUTION = 100_000_000n;

const morphoBlueParameters = encodeAbiParameters(
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
            morpho: "0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb" as `0x${string}`,
            collateralToken: WSTETH_ADDRESS_MAINNET,
            oracle: "0x48F7E36EB6B826B2dF4B2E630B62Cd25e89E40e2" as `0x${string}`,
            irm: "0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC" as `0x${string}`,
            lltv: BigInt("860000000000000000"),
        },
    ],
);

export const MAINNET_MORPHO_BLUE_WSTETH_USDC_182DAY: HyperdriveInstanceConfig<"MorphoBlue"> =
    {
        name: MAINNET_MORPHO_BLUE_WSTETH_USDC_182DAY_NAME,
        prefix: "MorphoBlue",
        coordinatorAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName(
                MAINNET_MORPHO_BLUE_COORDINATOR_NAME,
            ).address,
        deploymentId: keccak256(
            toHex(MAINNET_MORPHO_BLUE_WSTETH_USDC_182DAY_NAME),
        ),
        salt: toBytes32("0x42080085"),
        extraData: morphoBlueParameters,
        contribution: CONTRIBUTION,
        fixedAPR: parseEther("0.04"),
        timestretchAPR: parseEther("0.075"),
        options: async (hre) => ({
            extraData: "0x",
            asBase: true,
            destination: (await hre.getNamedAccounts())["deployer"] as Address,
        }),
        // Prepare to deploy the contract by setting approvals.
        prepare: async (hre, options) => {
            let pc = await hre.viem.getPublicClient();
            let baseToken = await hre.viem.getContractAt(
                "contracts/src/interfaces/IERC20.sol:IERC20",
                USDC_ADDRESS_MAINNET,
            );
            let tx = await baseToken.write.approve([
                hre.hyperdriveDeploy.deployments.byName(
                    MAINNET_MORPHO_BLUE_COORDINATOR_NAME,
                ).address,
                CONTRIBUTION,
            ]);
            await pc.waitForTransactionReceipt({ hash: tx });
        },
        poolDeployConfig: async (hre) => {
            return {
                baseToken: USDC_ADDRESS_MAINNET,
                vaultSharesToken: zeroAddress,
                circuitBreakerDelta: parseEther("0.075"),
                minimumShareReserves: 1_000_000n,
                minimumTransactionAmount: 1_000_000n,
                positionDuration: parseDuration(SIX_MONTHS),
                checkpointDuration: parseDuration("1 day"),
                timeStretch: 0n,
                governance: (await hre.getNamedAccounts())[
                    "deployer"
                ] as Address,
                feeCollector: zeroAddress,
                sweepCollector: zeroAddress,
                checkpointRewarder: zeroAddress,
                ...(await getLinkerDetails(
                    hre,
                    hre.hyperdriveDeploy.deployments.byName(
                        MAINNET_FACTORY_NAME,
                    ).address,
                )),
                fees: {
                    curve: parseEther("0.01"),
                    flat: normalizeFee(parseEther("0.0005"), SIX_MONTHS),
                    governanceLP: parseEther("0.15"),
                    governanceZombie: parseEther("0.03"),
                },
            };
        },
    };
