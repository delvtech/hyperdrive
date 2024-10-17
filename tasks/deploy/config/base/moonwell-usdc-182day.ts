import { Address, keccak256, parseEther, toBytes } from "viem";
import {
    HyperdriveInstanceConfig,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";
import {
    MOONWELL_USDC_ADDRESS_BASE,
    SIX_MONTHS,
    USDC_ADDRESS_BASE,
} from "../../lib/constants";
import { BASE_ERC4626_COORDINATOR_NAME } from "./erc4626-coordinator";
import { BASE_FACTORY_NAME } from "./factory";

// The name of the pool.
export const BASE_MOONWELL_USDC_182DAY_NAME =
    "ElementDAO 182 Day Moonwell USDC Hyperdrive";

// USDC only has 6 decimals.
const CONTRIBUTION = 100_000_000n;

export const BASE_MOONWELL_USDC_182DAY: HyperdriveInstanceConfig<"ERC4626"> = {
    name: BASE_MOONWELL_USDC_182DAY_NAME,
    prefix: "ERC4626",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(BASE_ERC4626_COORDINATOR_NAME)
            .address,
    deploymentId: keccak256(toBytes(BASE_MOONWELL_USDC_182DAY_NAME + "1")),
    salt: toBytes32("0x69421"),
    extraData: "0x",
    contribution: CONTRIBUTION,
    // The moonwell EURC rate is currently at 12%, but we have a cap on our
    // fixed rate of 10%. This is the link to the vaults page: https://moonwell.fi/vaults
    fixedAPR: parseEther("0.1"),
    timestretchAPR: parseEther("0.075"),
    options: async (hre) => ({
        extraData: "0x",
        asBase: true,
        destination: (await hre.getNamedAccounts())["deployer"] as Address,
    }),
    // Prepare to deploy the contract by setting approvals.
    prepare: async (hre) => {
        let baseToken = await hre.viem.getContractAt(
            "contracts/src/interfaces/IERC20.sol:IERC20",
            USDC_ADDRESS_BASE,
        );
        let tx = await baseToken.write.approve([
            hre.hyperdriveDeploy.deployments.byName(
                BASE_ERC4626_COORDINATOR_NAME,
            ).address,
            CONTRIBUTION,
        ]);
        let pc = await hre.viem.getPublicClient();
        await pc.waitForTransactionReceipt({ hash: tx });
    },
    poolDeployConfig: async (hre) => {
        let factoryContract = await hre.viem.getContractAt(
            "HyperdriveFactory",
            hre.hyperdriveDeploy.deployments.byName(BASE_FACTORY_NAME).address,
        );
        return {
            baseToken: USDC_ADDRESS_BASE,
            vaultSharesToken: MOONWELL_USDC_ADDRESS_BASE,
            circuitBreakerDelta: parseEther("0.075"),
            minimumShareReserves: parseEther("0.001"),
            minimumTransactionAmount: 1_000_000n,
            positionDuration: parseDuration(SIX_MONTHS),
            checkpointDuration: parseDuration("1 day"),
            timeStretch: 0n,
            governance: await factoryContract.read.governance(),
            feeCollector: await factoryContract.read.feeCollector(),
            sweepCollector: await factoryContract.read.sweepCollector(),
            checkpointRewarder: await factoryContract.read.checkpointRewarder(),
            ...(await getLinkerDetails(
                hre,
                hre.hyperdriveDeploy.deployments.byName(BASE_FACTORY_NAME)
                    .address,
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
