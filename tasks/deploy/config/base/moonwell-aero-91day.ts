import { Address, keccak256, parseEther, toBytes } from "viem";
import {
    HyperdriveInstanceConfig,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";
import {
    MOONWELL_AERO_ADDRESS_BASE,
    THREE_MONTHS,
    AERO_ADDRESS_BASE,
} from "../../lib/constants";
import { BASE_ERC4626_COORDINATOR_NAME } from "./erc4626-coordinator";
import { BASE_FACTORY_NAME } from "./factory";

// The name of the pool.
export const BASE_MOONWELL_AERO_91DAY_NAME =
    "ElementDAO 91 Day Moonwell AERO Hyperdrive";

// The initial contribution of the pool.
const CONTRIBUTION = parseEther("85");

export const BASE_MOONWELL_AERO_91DAY: HyperdriveInstanceConfig<"ERC4626"> = {
    name: BASE_MOONWELL_AERO_91DAY_NAME,
    prefix: "ERC4626",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(BASE_ERC4626_COORDINATOR_NAME)
            .address,
    deploymentId: keccak256(toBytes(BASE_MOONWELL_AERO_91DAY_NAME)),
    salt: toBytes32("0x69420"),
    extraData: "0x",
    contribution: CONTRIBUTION,
    fixedAPR: parseEther("0.10"),
    timestretchAPR: parseEther("0.05"),
    options: async (hre) => ({
        extraData: "0x",
        asBase: true,
        destination: (await hre.getNamedAccounts())["deployer"] as Address,
    }),
    // Prepare to deploy the contract by setting approvals.
    prepare: async (hre) => {
        let baseToken = await hre.viem.getContractAt(
            "contracts/src/interfaces/IERC20.sol:IERC20",
            AERO_ADDRESS_BASE,
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
            baseToken: AERO_ADDRESS_BASE,
            vaultSharesToken: MOONWELL_AERO_ADDRESS_BASE,
            circuitBreakerDelta: parseEther("0.05"),
            minimumShareReserves: parseEther("0.001"),
            minimumTransactionAmount: parseEther("0.001"),
            positionDuration: parseDuration(THREE_MONTHS),
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
                flat: normalizeFee(parseEther("0.0005"), THREE_MONTHS),
                governanceLP: parseEther("0.15"),
                governanceZombie: parseEther("0.03"),
            },
        };
    },
};
