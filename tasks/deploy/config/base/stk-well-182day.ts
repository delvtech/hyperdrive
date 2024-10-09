import { Address, keccak256, parseEther, toHex } from "viem";
import {
    HyperdriveInstanceConfig,
    SIX_MONTHS,
    STK_WELL_ADDRESS_BASE,
    WELL_ADDRESS_BASE,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";
import { BASE_FACTORY_NAME } from "./factory";
import { BASE_STK_WELL_COORDINATOR_NAME } from "./stk-well-coordinator";

export const BASE_STK_WELL_182DAY_NAME =
    "ElementDAO 182 Day Moonwell StkWell Hyperdrive";

// WELL is currently worth ~$0.03, so this is a contribution of around $80.
const CONTRIBUTION = parseEther("2700");

export const BASE_STK_WELL_182DAY: HyperdriveInstanceConfig<"StkWell"> = {
    name: BASE_STK_WELL_182DAY_NAME,
    prefix: "StkWell",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(BASE_STK_WELL_COORDINATOR_NAME)
            .address,
    deploymentId: keccak256(toHex(BASE_STK_WELL_182DAY_NAME)),
    salt: toBytes32("0x42080085"),
    extraData: "0x",
    contribution: CONTRIBUTION,
    // NOTE: The latest variable rate on Moonwell's Staked Well market is
    // 10.53% APY:
    //
    // https://moonwell.fi/stake/base
    fixedAPR: parseEther("0.1"),
    timestretchAPR: parseEther("0.05"),
    options: async (hre) => ({
        extraData: "0x",
        asBase: true,
        destination: (await hre.getNamedAccounts())["deployer"] as Address,
    }),
    // Prepare to deploy the contract by setting approvals.
    prepare: async (hre) => {
        let pc = await hre.viem.getPublicClient();
        let baseToken = await hre.viem.getContractAt(
            "contracts/src/interfaces/IERC20.sol:IERC20",
            WELL_ADDRESS_BASE,
        );
        let tx = await baseToken.write.approve([
            hre.hyperdriveDeploy.deployments.byName(
                BASE_STK_WELL_COORDINATOR_NAME,
            ).address,
            CONTRIBUTION,
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
    },
    poolDeployConfig: async (hre) => {
        let factoryContract = await hre.viem.getContractAt(
            "HyperdriveFactory",
            hre.hyperdriveDeploy.deployments.byName(BASE_FACTORY_NAME).address,
        );
        return {
            baseToken: WELL_ADDRESS_BASE,
            vaultSharesToken: STK_WELL_ADDRESS_BASE,
            circuitBreakerDelta: parseEther("0.05"),
            minimumShareReserves: parseEther("0.001"),
            minimumTransactionAmount: parseEther("0.001"),
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
