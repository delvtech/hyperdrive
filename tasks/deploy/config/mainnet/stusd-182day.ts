import { Address, keccak256, parseEther, toBytes, zeroAddress } from "viem";
import {
    HyperdriveInstanceConfig,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";
import {
    SIX_MONTHS,
    STUSD_ADDRESS_MAINNET,
    USDA_ADDRESS_MAINNET,
} from "../../lib/constants";
import { MAINNET_ERC4626_COORDINATOR_NAME } from "./erc4626-coordinator";
import { MAINNET_FACTORY_NAME } from "./factory";

// The name of the pool.
export const MAINNET_STUSD_182DAY_NAME = "ElementDAO 182 Day stUSD Hyperdrive";

// The initial contribution of the pool.
const CONTRIBUTION = parseEther("100");

export const MAINNET_STUSD_182DAY: HyperdriveInstanceConfig<"ERC4626"> = {
    name: MAINNET_STUSD_182DAY_NAME,
    prefix: "ERC4626",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(
            MAINNET_ERC4626_COORDINATOR_NAME,
        ).address,
    deploymentId: keccak256(toBytes(MAINNET_STUSD_182DAY_NAME)),
    salt: toBytes32("0x69420"),
    extraData: "0x",
    contribution: CONTRIBUTION,
    fixedAPR: parseEther("0.0829"),
    timestretchAPR: parseEther("0.1"),
    options: async (hre) => ({
        extraData: "0x",
        asBase: true,
        destination: (await hre.getNamedAccounts())["deployer"] as Address,
    }),
    // Prepare to deploy the contract by setting approvals.
    prepare: async (hre) => {
        let baseToken = await hre.viem.getContractAt(
            "contracts/src/interfaces/IERC20.sol:IERC20",
            USDA_ADDRESS_MAINNET,
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
        return {
            baseToken: USDA_ADDRESS_MAINNET,
            vaultSharesToken: STUSD_ADDRESS_MAINNET,
            circuitBreakerDelta: parseEther("0.75"),
            minimumShareReserves: parseEther("0.001"),
            minimumTransactionAmount: parseEther("0.001"),
            positionDuration: parseDuration(SIX_MONTHS),
            checkpointDuration: parseDuration("1 day"),
            timeStretch: 0n,
            // TODO: Read from the factory.
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