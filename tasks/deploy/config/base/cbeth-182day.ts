import {
    Address,
    encodeAbiParameters,
    keccak256,
    parseAbiParameters,
    parseEther,
    toBytes,
    zeroAddress,
} from "viem";
import {
    HyperdriveInstanceConfig,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";
import {
    CBETH_ADDRESS_BASE,
    CHAINLINK_AGGREGATOR_CBETH_ETH_PROXY_BASE,
    SIX_MONTHS,
} from "../../lib/constants";
import { BASE_CHAINLINK_COORDINATOR_NAME } from "./chainlink-coordinator";
import { BASE_FACTORY_NAME } from "./factory";

// The name of the pool.
export const BASE_CBETH_182DAY_NAME = "ElementDAO 182 Day cbETH Hyperdrive";

// The initial contribution of the pool.
const CONTRIBUTION = parseEther("0.03");

export const BASE_CBETH_182DAY: HyperdriveInstanceConfig<"Chainlink"> = {
    name: BASE_CBETH_182DAY_NAME,
    prefix: "Chainlink",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(BASE_CHAINLINK_COORDINATOR_NAME)
            .address,
    deploymentId: keccak256(toBytes(BASE_CBETH_182DAY_NAME)),
    salt: toBytes32("0xababe"),
    extraData: encodeAbiParameters(parseAbiParameters("address, uint8"), [
        CHAINLINK_AGGREGATOR_CBETH_ETH_PROXY_BASE,
        18,
    ]),
    contribution: CONTRIBUTION,
    // NOTE: The market is bouncing around 3% on Defillama.
    fixedAPR: parseEther("0.03"),
    timestretchAPR: parseEther("0.035"),
    options: async (hre) => ({
        extraData: encodeAbiParameters(parseAbiParameters("address, uint8"), [
            CHAINLINK_AGGREGATOR_CBETH_ETH_PROXY_BASE,
            18,
        ]),
        asBase: false,
        destination: (await hre.getNamedAccounts())["deployer"] as Address,
    }),
    // Prepare to deploy the contract by setting approvals.
    prepare: async (hre) => {
        let vaultSharesToken = await hre.viem.getContractAt(
            "contracts/src/interfaces/IERC20.sol:IERC20",
            CBETH_ADDRESS_BASE,
        );
        let tx = await vaultSharesToken.write.approve([
            hre.hyperdriveDeploy.deployments.byName(
                BASE_CHAINLINK_COORDINATOR_NAME,
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
            baseToken: zeroAddress,
            vaultSharesToken: CBETH_ADDRESS_BASE,
            circuitBreakerDelta: parseEther("0.035"),
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
