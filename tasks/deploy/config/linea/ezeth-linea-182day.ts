import { Address, keccak256, parseEther, toBytes, zeroAddress } from "viem";
import {
    ETH_ADDRESS,
    EZETH_ADDRESS_LINEA,
    HyperdriveInstanceConfig,
    SIX_MONTHS,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";
import { LINEA_EZETH_COORDINATOR_NAME } from "./ezeth-linea-coordinator";
import { LINEA_FACTORY_NAME } from "./factory";

// The name of the pool.
export const LINEA_EZETH_182DAY_NAME =
    "ElementDAO 182 Day Renzo xezETH Hyperdrive";

// The initial contribution of the pool.
const CONTRIBUTION = parseEther("0.04");

export const LINEA_EZETH_182DAY: HyperdriveInstanceConfig<"EzETHLinea"> = {
    name: LINEA_EZETH_182DAY_NAME,
    prefix: "EzETHLinea",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(LINEA_EZETH_COORDINATOR_NAME)
            .address,
    deploymentId: keccak256(toBytes(LINEA_EZETH_182DAY_NAME)),
    salt: toBytes32("0xababe"),
    extraData: "0x",
    contribution: CONTRIBUTION,
    fixedAPR: parseEther("0.05"),
    timestretchAPR: parseEther("0.1"),
    options: async (hre) => ({
        asBase: false,
        extraData: "0x",
        destination: (await hre.getNamedAccounts())["deployer"] as Address,
    }),
    prepare: async (hre) => {
        // approve the coordinator
        let vaultSharesToken = await hre.viem.getContractAt(
            "openzeppelin/token/ERC20/IERC20.sol:IERC20",
            EZETH_ADDRESS_LINEA,
        );
        let pc = await hre.viem.getPublicClient();
        let tx = await vaultSharesToken.write.approve([
            hre.hyperdriveDeploy.deployments.byName(
                LINEA_EZETH_COORDINATOR_NAME,
            ).address,
            CONTRIBUTION,
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
    },
    poolDeployConfig: async (hre) => {
        return {
            baseToken: ETH_ADDRESS,
            vaultSharesToken: EZETH_ADDRESS_LINEA,
            circuitBreakerDelta: parseEther("0.075"),
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
                hre.hyperdriveDeploy.deployments.byName(LINEA_FACTORY_NAME)
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
