import { Address, parseEther, zeroAddress } from "viem";
import {
    HyperdriveInstanceConfig,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";
import {
    MAINNET_DAI_ADDRESS,
    MAINNET_SDAI_ADDRESS,
    SIX_MONTHS,
} from "../../lib/constants";
import { MAINNET_ERC4626_COORDINATOR_NAME } from "./erc4626-coordinator";
import { MAINNET_FACTORY_NAME } from "./factory";

// FIXME: Double-check this.
// The name of the pool.
export const MAINNET_DAI_182DAY_NAME = "ElementDAO 182 day sDAI Hyperdrive";

// The initial contribution of the pool.
const CONTRIBUTION = parseEther("100e18");

export const MAINNET_DAI_182DAY: HyperdriveInstanceConfig<"ERC4626"> = {
    name: MAINNET_DAI_182DAY_NAME,
    prefix: "ERC4626",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(
            MAINNET_ERC4626_COORDINATOR_NAME,
        ).address,
    deploymentId: toBytes32(MAINNET_DAI_182DAY_NAME),
    salt: toBytes32("0x69420"),
    extraData: "0x",
    contribution: CONTRIBUTION,
    // FIXME: Double-check this one more time
    fixedAPR: parseEther("0.08"),
    // FIXME: Double-check this one more time
    timestretchAPR: parseEther("0.05"),
    options: async (hre) => ({
        extraData: "0x",
        asBase: true,
        destination: (await hre.getNamedAccounts())["deployer"] as Address,
    }),
    // Prepare to deploy the contract by setting approvals and minting sufficient
    // tokens for the contribution.
    prepare: async (hre) => {
        let baseToken = await hre.viem.getContractAt(
            "contracts/src/interfaces/IERC20.sol:IERC20",
            MAINNET_DAI_ADDRESS,
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
        // FIXME: Re-check this.
        return {
            baseToken: MAINNET_DAI_ADDRESS,
            vaultSharesToken: MAINNET_SDAI_ADDRESS,
            circuitBreakerDelta: parseEther("0.05"),
            minimumShareReserves: parseEther("10"),
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
