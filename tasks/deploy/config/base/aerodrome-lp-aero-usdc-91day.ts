import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Address, keccak256, parseEther, toBytes, zeroAddress } from "viem";
import {
    HyperdriveInstanceConfig,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";
import {
    AERO_USDC_GAUGE_ADDRESS_BASE,
    AERO_USDC_LP_ADDRESS_BASE,
    THREE_MONTHS,
} from "../../lib/constants";
import { BASE_AERODROME_LP_COORDINATOR_NAME } from "./aerodrome-lp-coordinator";
import { BASE_FACTORY_NAME } from "./factory";

// The name of the pool.
export const BASE_AERODROME_LP_AERO_USDC_91DAY_NAME =
    "ElementDAO 91 Day Aerodrome LP AERO-USDC Hyperdrive";

const CONTRIBUTION = parseEther("100"); // 1e20

export const BASE_AERODROME_LP_AERO_USDC_91DAY: HyperdriveInstanceConfig<"AerodromeLp"> =
    {
        name: BASE_AERODROME_LP_AERO_USDC_91DAY_NAME,
        prefix: "AerodromeLp",
        coordinatorAddress: async (hre) =>
            hre.hyperdriveDeploy.deployments.byName(
                BASE_AERODROME_LP_COORDINATOR_NAME,
            ).address,
        deploymentId: keccak256(
            toBytes(BASE_AERODROME_LP_AERO_USDC_91DAY_NAME),
        ),
        salt: toBytes32("0x69420"),
        extraData: AERO_USDC_GAUGE_ADDRESS_BASE,
        contribution: CONTRIBUTION,
        fixedAPR: parseEther("0.08"),
        timestretchAPR: parseEther("0.075"),
        options: async (hre: HardhatRuntimeEnvironment) => ({
            extraData: "0x",
            asBase: true,
            destination: (await hre.getNamedAccounts())["deployer"] as Address,
        }),
        // Prepare to deploy the contract by setting approvals.
        prepare: async (hre: HardhatRuntimeEnvironment) => {
            let baseToken = await hre.viem.getContractAt(
                "contracts/src/interfaces/IERC20.sol:IERC20",
                AERO_USDC_LP_ADDRESS_BASE,
            );
            let tx = await baseToken.write.approve([
                hre.hyperdriveDeploy.deployments.byName(
                    BASE_AERODROME_LP_COORDINATOR_NAME,
                ).address,
                CONTRIBUTION,
            ]);
            let pc = await hre.viem.getPublicClient();
            await pc.waitForTransactionReceipt({ hash: tx });
        },
        poolDeployConfig: async (hre: HardhatRuntimeEnvironment) => {
            let factoryContract = await hre.viem.getContractAt(
                "HyperdriveFactory",
                hre.hyperdriveDeploy.deployments.byName(BASE_FACTORY_NAME)
                    .address,
            );
            return {
                baseToken: AERO_USDC_LP_ADDRESS_BASE,
                vaultSharesToken: zeroAddress,
                circuitBreakerDelta: parseEther("0.075"),
                minimumShareReserves: 100_000_000n, //1e8
                minimumTransactionAmount: 100_000_000n, //1e8
                positionDuration: parseDuration(THREE_MONTHS),
                checkpointDuration: parseDuration("1 day"),
                timeStretch: 0n,
                governance: await factoryContract.read.hyperdriveGovernance(),
                feeCollector: await factoryContract.read.feeCollector(),
                sweepCollector: await factoryContract.read.sweepCollector(),
                checkpointRewarder:
                    await factoryContract.read.checkpointRewarder(),
                ...(await getLinkerDetails(
                    hre,
                    hre.hyperdriveDeploy.deployments.byName(BASE_FACTORY_NAME)
                        .address,
                )),
                fees: {
                    curve: parseEther("0.01"),
                    flat: normalizeFee(parseEther("0.0005"), THREE_MONTHS),
                    governanceLP: parseEther("0.15"),
                    governanceZombie: parseEther("0.03"),
                },
            };
        },
    };
