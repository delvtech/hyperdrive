import { Address, parseEther, zeroAddress } from "viem";
import {
    ETH_ADDRESS,
    HyperdriveInstanceConfig,
    MAINNET_STETH_ADDRESS,
    SIX_MONTHS,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";
import { MAINNET_FACTORY_NAME } from "./factory";
import { MAINNET_STETH_COORDINATOR_NAME } from "./steth-coordinator";

// FIXME: Double-check this.
//
// The name of the pool.
export const MAINNET_STETH_182DAY_NAME = "ElementDAO 182 day stETH Hyperdrive";

// The initial contribution of the pool.
const CONTRIBUTION = parseEther("0.1");

export const MAINNET_STETH_182DAY: HyperdriveInstanceConfig<"StETH"> = {
    name: MAINNET_STETH_182DAY_NAME,
    prefix: "StETH",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(MAINNET_STETH_COORDINATOR_NAME)
            .address,
    deploymentId: toBytes32(MAINNET_STETH_182DAY_NAME),
    salt: toBytes32("0xababe"),
    extraData: "0x",
    contribution: CONTRIBUTION,
    // FIXME: Double-check this.
    fixedAPR: parseEther("0.03"),
    // FIXME: Double-check this.
    timestretchAPR: parseEther("0.035"),
    options: async (hre) => ({
        asBase: false,
        extraData: "0x",
        destination: (await hre.getNamedAccounts())["deployer"] as Address,
    }),
    prepare: async (hre) => {
        // approve the coordinator
        let vaultSharesToken = await hre.viem.getContractAt(
            "ILido",
            MAINNET_STETH_ADDRESS,
        );
        let pc = await hre.viem.getPublicClient();
        let tx = await vaultSharesToken.write.approve([
            hre.hyperdriveDeploy.deployments.byName(
                MAINNET_STETH_COORDINATOR_NAME,
            ).address,
            await vaultSharesToken.read.getPooledEthByShares([CONTRIBUTION]),
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
    },
    poolDeployConfig: async (hre) => {
        // FIXME: Double-check this.
        return {
            baseToken: ETH_ADDRESS,
            vaultSharesToken: MAINNET_STETH_ADDRESS,
            circuitBreakerDelta: parseEther("0.035"),
            minimumShareReserves: parseEther("0.001"),
            minimumTransactionAmount: parseEther("0.001"),
            positionDuration: parseDuration(SIX_MONTHS),
            checkpointDuration: parseDuration("1 day"),
            timeStretch: 0n,
            governance: (await hre.getNamedAccounts())["deployer"] as Address,
            feeCollector: zeroAddress,
            sweepCollector: zeroAddress,
            checkpointRewarder: zeroAddress,
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
