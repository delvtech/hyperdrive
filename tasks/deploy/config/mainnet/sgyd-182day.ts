import { Address, keccak256, parseEther, toBytes } from "viem";
import {
    HyperdriveInstanceConfig,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";
import {
    GYD_ADDRESS_MAINNET,
    SGYD_ADDRESS_MAINNET,
    SIX_MONTHS,
} from "../../lib/constants";
import { MAINNET_ERC4626_COORDINATOR_NAME } from "./erc4626-coordinator";
import { MAINNET_FACTORY_NAME } from "./factory";

// The name of the pool.
export const MAINNET_SGYD_182DAY_NAME = "ElementDAO 182 Day sGYD Hyperdrive";

// The initial contribution of the pool.
const CONTRIBUTION = parseEther("100");

export const MAINNET_SGYD_182DAY: HyperdriveInstanceConfig<"ERC4626"> = {
    name: MAINNET_SGYD_182DAY_NAME,
    prefix: "ERC4626",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(
            MAINNET_ERC4626_COORDINATOR_NAME,
        ).address,
    deploymentId: keccak256(toBytes(MAINNET_SGYD_182DAY_NAME + "1")),
    salt: toBytes32("0x69421"),
    extraData: "0x",
    contribution: CONTRIBUTION,
    // The current fixed rate on sGYD is 11.85%, but our maximum is 10%:
    // https://app.gyro.finance/sgyd/ethereum/
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
            GYD_ADDRESS_MAINNET,
        );
        let tx = await baseToken.write.approve([
            hre.hyperdriveDeploy.deployments.byName(
                MAINNET_ERC4626_COORDINATOR_NAME,
            ).address,
            CONTRIBUTION,
        ]);
        let pc = await hre.viem.getPublicClient();
        await pc.waitForTransactionReceipt({ hash: tx });
    },
    poolDeployConfig: async (hre) => {
        let factoryContract = await hre.viem.getContractAt(
            "HyperdriveFactory",
            hre.hyperdriveDeploy.deployments.byName(MAINNET_FACTORY_NAME)
                .address,
        );
        return {
            baseToken: GYD_ADDRESS_MAINNET,
            vaultSharesToken: SGYD_ADDRESS_MAINNET,
            circuitBreakerDelta: parseEther("0.075"),
            minimumShareReserves: parseEther("0.001"),
            minimumTransactionAmount: parseEther("0.001"),
            positionDuration: parseDuration(SIX_MONTHS),
            checkpointDuration: parseDuration("1 day"),
            timeStretch: 0n,
            governance: await factoryContract.read.hyperdriveGovernance(),
            feeCollector: await factoryContract.read.feeCollector(),
            sweepCollector: await factoryContract.read.sweepCollector(),
            checkpointRewarder: await factoryContract.read.checkpointRewarder(),
            ...(await getLinkerDetails(
                hre,
                hre.hyperdriveDeploy.deployments.byName(MAINNET_FACTORY_NAME)
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
