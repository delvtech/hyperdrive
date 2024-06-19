import { Address, parseEther, toFunctionSelector } from "viem";
import {
    HyperdriveInstanceConfig,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";
import { SEPOLIA_CHECKPOINT_REWARDER_NAME } from "./checkpoint-rewarder";
import { SEPOLIA_ERC4626_COORDINATOR_NAME } from "./erc4626-coordinator";
import {
    SEPOLIA_FACTORY_GOVERNANCE_ADDRESS,
    SEPOLIA_FACTORY_NAME,
} from "./factory";

export const SEPOLIA_DAI_30DAY_NAME = "DAI_30_DAY";

const CONTRIBUTION = parseEther("10000");

export const SEPOLIA_DAI_30DAY: HyperdriveInstanceConfig<"ERC4626"> = {
    name: SEPOLIA_DAI_30DAY_NAME,
    prefix: "ERC4626",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName(
            SEPOLIA_ERC4626_COORDINATOR_NAME,
        ).address,
    deploymentId: toBytes32(SEPOLIA_DAI_30DAY_NAME),
    salt: toBytes32("0x69420"),
    extraData: "0x",
    contribution: CONTRIBUTION,
    fixedAPR: parseEther("0.10"),
    timestretchAPR: parseEther("0.10"),
    options: async (hre) => ({
        extraData: "0x",
        asBase: true,
        destination: (await hre.getNamedAccounts())["deployer"] as Address,
    }),
    prepare: async (hre, options) => {
        let pc = await hre.viem.getPublicClient();
        let baseToken = await hre.hyperdriveDeploy.ensureDeployed(
            "DAI",
            "ERC20Mintable",
            [
                "DAI",
                "DAI",
                18,
                (await hre.getNamedAccounts())["deployer"] as Address,
                true,
                parseEther("10000"),
            ],
            options,
        );
        let vaultSharesToken = await hre.hyperdriveDeploy.ensureDeployed(
            "SDAI",
            "MockERC4626",
            [
                hre.hyperdriveDeploy.deployments.byName("DAI").address,
                "Savings DAI",
                "SDAI",
                parseEther("0.10"),
                (await hre.getNamedAccounts())["deployer"] as Address,
                true,
                parseEther("10000"),
            ],
            options,
        );

        // allow minting by the public
        let tx = await baseToken.write.setPublicCapability([
            toFunctionSelector("mint(uint256)"),
            true,
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
        tx = await vaultSharesToken.write.setPublicCapability([
            toFunctionSelector("mint(uint256)"),
            true,
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
        tx = await baseToken.write.setPublicCapability([
            toFunctionSelector("mint(address,uint256)"),
            true,
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
        tx = await vaultSharesToken.write.setPublicCapability([
            toFunctionSelector("mint(address,uint256)"),
            true,
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });

        // approve the coordinator for the contribution
        tx = await baseToken.write.approve([
            hre.hyperdriveDeploy.deployments.byName("ERC4626_COORDINATOR")
                .address,
            CONTRIBUTION,
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });

        // mint some tokens for the contribution
        tx = await baseToken.write.mint([CONTRIBUTION]);
        await pc.waitForTransactionReceipt({ hash: tx });
    },
    poolDeployConfig: async (hre) => {
        return {
            baseToken: hre.hyperdriveDeploy.deployments.byName("DAI").address,
            vaultSharesToken:
                hre.hyperdriveDeploy.deployments.byName("SDAI").address,
            circuitBreakerDelta: parseEther("0.6"),
            minimumShareReserves: parseEther("10"),
            minimumTransactionAmount: parseEther("0.001"),
            positionDuration: parseDuration("30 days"),
            checkpointDuration: parseDuration("1 day"),
            timeStretch: 0n,
            governance: SEPOLIA_FACTORY_GOVERNANCE_ADDRESS,
            feeCollector: SEPOLIA_FACTORY_GOVERNANCE_ADDRESS,
            sweepCollector: SEPOLIA_FACTORY_GOVERNANCE_ADDRESS,
            checkpointRewarder: hre.hyperdriveDeploy.deployments.byName(
                SEPOLIA_CHECKPOINT_REWARDER_NAME,
            ).address,
            ...(await getLinkerDetails(
                hre,
                hre.hyperdriveDeploy.deployments.byName(SEPOLIA_FACTORY_NAME)
                    .address,
            )),
            fees: {
                curve: parseEther("0.01"),
                flat: normalizeFee(parseEther("0.0005"), "30 days"),
                governanceLP: parseEther("0.15"),
                governanceZombie: parseEther("0.03"),
            },
        };
    },
};
