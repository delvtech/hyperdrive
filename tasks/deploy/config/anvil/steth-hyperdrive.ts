import { Address, parseEther } from "viem";
import {
    HyperdriveInstanceConfig,
    getLinkerDetails,
    normalizeFee,
    parseDuration,
    toBytes32,
} from "../../lib";
import { ANVIL_FACTORY_NAME } from "./factory";

let { env } = process;

const CONTRIBUTION = parseEther(env.STETH_HYPERDRIVE_CONTRIBUTION!);

// ERC4626 instance deployed to anvil and used for devnet/testnet.
export const ANVIL_STETH_HYPERDRIVE: HyperdriveInstanceConfig<"StETH"> = {
    name: "STETH_HYPERDRIVE",
    prefix: "StETH",
    coordinatorAddress: async (hre) =>
        hre.hyperdriveDeploy.deployments.byName("STETH_COORDINATOR").address,
    deploymentId: toBytes32("STETH_HYPERDRIVE"),
    salt: toBytes32("0xababe"),
    extraData: "0x",
    contribution: CONTRIBUTION,
    fixedAPR: parseEther(env.STETH_HYPERDRIVE_FIXED_APR!),
    timestretchAPR: parseEther(env.STETH_HYPERDRIVE_TIME_STRETCH_APR!),
    options: async (hre) => ({
        extraData: "0x",
        asBase: false,
        destination: (await hre.getNamedAccounts())["deployer"] as Address,
    }),
    // Prepare for instance deployment by deploying the StETH token if needed,
    // approving the coordinator for the contribution amount.
    // When finished, transfer ownership of the base and vault token
    // to the admin address.
    prepare: async (hre) => {
        let vaultSharesToken = await hre.viem.getContractAt(
            "MockLido",
            hre.hyperdriveDeploy.deployments.byName("STETH").address,
        );
        let pc = await hre.viem.getPublicClient();
        // mint the contribution
        let tx = await vaultSharesToken.write.mint([CONTRIBUTION]);
        await pc.waitForTransactionReceipt({ hash: tx });
        // approve the coordinator
        tx = await vaultSharesToken.write.approve([
            hre.hyperdriveDeploy.deployments.byName("STETH_COORDINATOR")
                .address,
            CONTRIBUTION + parseEther("1"),
        ]);
        await pc.waitForTransactionReceipt({ hash: tx });
    },
    poolDeployConfig: async (hre) => {
        return {
            baseToken: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
            vaultSharesToken:
                hre.hyperdriveDeploy.deployments.byName("STETH").address,
            circuitBreakerDelta: parseEther(
                env.STETH_HYPERDRIVE_CIRCUIT_BREAKER_DELTA!,
            ),
            minimumShareReserves: parseEther(
                env.STETH_HYPERDRIVE_MINIMUM_SHARE_RESERVES!,
            ),
            minimumTransactionAmount: parseEther(
                env.STETH_HYPERDRIVE_MINIMUM_TRANSACTION_AMOUNT!,
            ),
            positionDuration: parseDuration(
                `${env.STETH_HYPERDRIVE_POSITION_DURATION} days` as any,
            ),
            checkpointDuration: parseDuration(
                `${env.STETH_HYPERDRIVE_CHECKPOINT_DURATION} hours` as any,
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
                curve: parseEther(env.STETH_HYPERDRIVE_CURVE_FEE!),
                flat: normalizeFee(
                    parseEther(env.STETH_HYPERDRIVE_FLAT_FEE!),
                    `${env.STETH_HYPERDRIVE_POSITION_DURATION} days` as any,
                ),
                governanceLP: parseEther(
                    env.STETH_HYPERDRIVE_GOVERNANCE_LP_FEE!,
                ),
                governanceZombie: parseEther(
                    env.STETH_HYPERDRIVE_GOVERNANCE_ZOMBIE_FEE!,
                ),
            },
        };
    },
};
