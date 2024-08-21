import { Address, keccak256, parseEther, toBytes, zeroAddress } from "viem";
import {
    ETH_ADDRESS,
    HyperdriveInstanceConfig,
    RETH_ADDRESS_MAINNET,
    SIX_MONTHS,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";
import { MAINNET_FACTORY_NAME } from "./factory";
import { MAINNET_RETH_COORDINATOR_NAME } from "./reth-coordinator";

// The name of the pool.
export const MAINNET_RETH_182DAY_NAME = "ElementDAO 182 Day rETH Hyperdrive";

// The initial contribution of the pool.
const CONTRIBUTION = parseEther("0.01");

export const MAINNET_RETH_182DAY: HyperdriveInstanceConfig<"RETH"> = {
    name: MAINNET_RETH_182DAY_NAME,
    prefix: "RETH",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(MAINNET_RETH_COORDINATOR_NAME)
            .address,
    deploymentId: keccak256(toBytes(MAINNET_RETH_182DAY_NAME)),
    salt: toBytes32("0xababe"),
    extraData: "0x",
    contribution: CONTRIBUTION,
    fixedAPR: parseEther("0.0277"),
    timestretchAPR: parseEther("0.035"),
    options: async (hre) => ({
        asBase: false,
        extraData: "0x",
        destination: (await hre.getNamedAccounts())["deployer"] as Address,
    }),
    prepare: async (hre) => {
        // approve the coordinator
        let vaultSharesToken = await hre.viem.getContractAt(
            "IRocketTokenRETH",
            RETH_ADDRESS_MAINNET,
        );
        let pc = await hre.viem.getPublicClient();
        let tx = await vaultSharesToken.write.approve([
            hre.hyperdriveDeploy.deployments.byName(
                MAINNET_RETH_COORDINATOR_NAME,
            ).address,
            CONTRIBUTION,
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
    },
    poolDeployConfig: async (hre) => {
        return {
            baseToken: ETH_ADDRESS,
            vaultSharesToken: RETH_ADDRESS_MAINNET,
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
