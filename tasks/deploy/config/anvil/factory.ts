import { Address, parseEther } from "viem";
import { HyperdriveFactoryConfig, parseDuration } from "../../lib";

let { env } = process;

// The name of the factory.
export const ANVIL_FACTORY_NAME = "ElementDAO Hyperdrive Factory";

// The name of the forwarder factory.
export const ANVIL_FACTORY_FORWARDER_NAME =
    "ElementDAO ERC20 Factory Forwarder";

export const ANVIL_FACTORY: HyperdriveFactoryConfig = {
    name: ANVIL_FACTORY_NAME,
    prepare: async (hre, options) => {
        await hre.hyperdriveDeploy.ensureDeployed(
            ANVIL_FACTORY_FORWARDER_NAME,
            "ERC20ForwarderFactory",
            ["FACTORY_FORWARDER"],
            options,
        );
    },
    constructorArguments: async (hre) => [
        {
            governance: env.ADMIN as Address,
            deployerCoordinatorManager: (await hre.getNamedAccounts())[
                "deployer"
            ] as Address,
            hyperdriveGovernance: env.ADMIN as Address,
            defaultPausers: [env.ADMIN as Address],
            feeCollector: env.ADMIN as Address,
            sweepCollector: env.ADMIN as Address,
            checkpointRewarder: hre.hyperdriveDeploy.deployments.byName(
                "CHECKPOINT_REWARDER",
            ).address,
            checkpointDurationResolution: parseDuration(
                `${env.FACTORY_CHECKPOINT_DURATION!} hours` as any,
            ),
            minCheckpointDuration: parseDuration(
                `${env.FACTORY_MIN_CHECKPOINT_DURATION!} hours` as any,
            ),
            maxCheckpointDuration: parseDuration(
                `${env.FACTORY_MAX_CHECKPOINT_DURATION!} hours` as any,
            ),
            minPositionDuration: parseDuration(
                `${env.FACTORY_MIN_POSITION_DURATION!} days` as any,
            ),
            maxPositionDuration: parseDuration(
                `${env.FACTORY_MAX_POSITION_DURATION!} days` as any,
            ),
            minCircuitBreakerDelta: parseEther(
                env.FACTORY_MIN_CIRCUIT_BREAKER_DELTA!,
            ),
            maxCircuitBreakerDelta: parseEther(
                env.FACTORY_MAX_CIRCUIT_BREAKER_DELTA!,
            ),
            minFixedAPR: parseEther(env.FACTORY_MIN_FIXED_APR!),
            maxFixedAPR: parseEther(env.FACTORY_MAX_FIXED_APR!),
            minTimeStretchAPR: parseEther(env.FACTORY_MIN_TIME_STRETCH_APR!),
            maxTimeStretchAPR: parseEther(env.FACTORY_MAX_TIME_STRETCH_APR!),
            minFees: {
                curve: parseEther(env.FACTORY_MIN_CURVE_FEE!),
                flat: parseEther(env.FACTORY_MIN_FLAT_FEE!),
                governanceLP: parseEther(env.FACTORY_MIN_GOVERNANCE_LP_FEE!),
                governanceZombie: parseEther(
                    env.FACTORY_MIN_GOVERNANCE_ZOMBIE_FEE!,
                ),
            },
            maxFees: {
                curve: parseEther(env.FACTORY_MAX_CURVE_FEE!),
                flat: parseEther(env.FACTORY_MAX_FLAT_FEE!),
                governanceLP: parseEther(env.FACTORY_MAX_GOVERNANCE_LP_FEE!),
                governanceZombie: parseEther(
                    env.FACTORY_MAX_GOVERNANCE_ZOMBIE_FEE!,
                ),
            },
            linkerFactory: hre.hyperdriveDeploy.deployments.byName(
                ANVIL_FACTORY_FORWARDER_NAME,
            ).address,
            linkerCodeHash: await (
                await hre.viem.getContractAt(
                    "ERC20ForwarderFactory",
                    hre.hyperdriveDeploy.deployments.byName(
                        ANVIL_FACTORY_FORWARDER_NAME,
                    ).address,
                )
            ).read.ERC20LINK_HASH(),
        },
        ANVIL_FACTORY_NAME,
    ],
};
