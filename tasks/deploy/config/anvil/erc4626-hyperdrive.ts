import { Address, maxUint256, parseEther, toFunctionSelector } from "viem";
import {
    HyperdriveInstanceConfig,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";
import { ANVIL_FACTORY_NAME } from "./factory";

let { env } = process;

const CONTRIBUTION = parseEther(env.ERC4626_HYPERDRIVE_CONTRIBUTION!);

// ERC4626 instance deployed to anvil and used for devnet/testnet.
export const ANVIL_ERC4626_HYPERDRIVE: HyperdriveInstanceConfig<"ERC4626"> = {
    name: "ERC4626_HYPERDRIVE",
    prefix: "ERC4626",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName("ERC4626_COORDINATOR").address,
    deploymentId: toBytes32("ERC4626_HYPERDRIVE"),
    salt: toBytes32("0x69420"),
    extraData: "0x",
    contribution: CONTRIBUTION,
    fixedAPR: parseEther(env.ERC4626_HYPERDRIVE_FIXED_APR!),
    timestretchAPR: parseEther(env.ERC4626_HYPERDRIVE_TIME_STRETCH_APR!),
    options: async (hre) => ({
        extraData: "0x",
        asBase: true,
        destination: (await hre.getNamedAccounts())["deployer"] as Address,
    }),
    // Prepare for instance deployment by deploying the tokens if needed,
    // setting permissions on the mint+burn functions of the base token
    // and approving the coordinator for the contribution amount.
    // When finished, transfer ownership of the base and vault token
    // to the admin address.
    prepare: async (hre, options) => {
        let pc = await hre.viem.getPublicClient();
        let baseToken = await hre.hyperdriveDeploy.ensureDeployed(
            "BASE_TOKEN",
            "ERC20Mintable",
            [
                env.BASE_TOKEN_NAME!,
                env.BASE_TOKEN_SYMBOL!,
                parseInt(env.BASE_TOKEN_DECIMALS!),
                env.ADMIN! as Address,
                env.IS_COMPETITION_MODE! === "true",
                maxUint256,
            ],
            options,
        );
        let vaultSharesToken = await hre.hyperdriveDeploy.ensureDeployed(
            "VAULT_SHARES_TOKEN",
            "MockERC4626",
            [
                hre.hyperdriveDeploy.deployments.byName("BASE_TOKEN").address,
                env.VAULT_NAME!,
                env.VAULT_SYMBOL!,
                parseEther(env.VAULT_STARTING_RATE!),
                env.ADMIN! as Address,
                env.IS_COMPETITION_MODE! === "true",
                maxUint256,
            ],
            options,
        );
        let tx = await baseToken.write.setPublicCapability([
            toFunctionSelector("mint(uint256)"),
            env.IS_COMPETITION_MODE! === "true",
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
        tx = await baseToken.write.setPublicCapability([
            toFunctionSelector("burn(uint256)"),
            env.IS_COMPETITION_MODE! === "true",
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
        tx = await baseToken.write.approve([
            hre.hyperdriveDeploy.deployments.byName("ERC4626_COORDINATOR")
                .address,
            CONTRIBUTION,
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
        tx = await baseToken.write.mint([CONTRIBUTION]);
        await pc.waitForTransactionReceipt({ hash: tx });
        tx = await baseToken.write.transferOwnership([env.ADMIN! as Address]);
        await pc.waitForTransactionReceipt({ hash: tx });
        tx = await vaultSharesToken.write.transferOwnership([
            env.ADMIN! as Address,
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
    },
    poolDeployConfig: async (hre) => {
        return {
            baseToken:
                hre.hyperdriveDeploy.deployments.byName("BASE_TOKEN").address,
            vaultSharesToken:
                hre.hyperdriveDeploy.deployments.byName("VAULT_SHARES_TOKEN")
                    .address,
            circuitBreakerDelta: parseEther(
                env.ERC4626_HYPERDRIVE_CIRCUIT_BREAKER_DELTA!,
            ),
            minimumShareReserves: parseEther(
                env.ERC4626_HYPERDRIVE_MINIMUM_SHARE_RESERVES!,
            ),
            minimumTransactionAmount: parseEther(
                env.ERC4626_HYPERDRIVE_MINIMUM_TRANSACTION_AMOUNT!,
            ),
            positionDuration: parseDuration(
                `${env.ERC4626_HYPERDRIVE_POSITION_DURATION} days` as any,
            ),
            checkpointDuration: parseDuration(
                `${env.ERC4626_HYPERDRIVE_CHECKPOINT_DURATION} hours` as any,
            ),
            timeStretch: 0n,
            governance: env.ADMIN! as Address,
            feeCollector: env.ADMIN! as Address,
            sweepCollector: env.ADMIN! as Address,
            checkpointRewarder: hre.hyperdriveDeploy.deployments.byName(
                "CHECKPOINT_REWARDER",
            ).address,
            ...(await getLinkerDetails(
                hre,
                hre.hyperdriveDeploy.deployments.byName(ANVIL_FACTORY_NAME)
                    .address,
            )),
            fees: {
                curve: parseEther(env.ERC4626_HYPERDRIVE_CURVE_FEE!),
                flat: normalizeFee(
                    parseEther(env.ERC4626_HYPERDRIVE_FLAT_FEE!),
                    `${env.ERC4626_HYPERDRIVE_POSITION_DURATION} days` as any,
                ),
                governanceLP: parseEther(
                    env.ERC4626_HYPERDRIVE_GOVERNANCE_LP_FEE!,
                ),
                governanceZombie: parseEther(
                    env.ERC4626_HYPERDRIVE_GOVERNANCE_ZOMBIE_FEE!,
                ),
            },
        };
    },
};
