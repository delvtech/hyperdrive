import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import hre from "hardhat";
import { ArtifactsMap } from "hardhat/types";
import {
    Address,
    ContractConstructorArgs,
    ContractFunctionArgs,
    Hex,
    toHex,
} from "viem";
import { z } from "zod";
import { HyperdriveDeployRuntimeOptions } from "./environment-extensions";
import { zAddress, zBytes32, zDuration, zEther, zHex } from "./types";

dayjs.extend(duration);

export type HREFn<T extends unknown = undefined> = (
    _hre: typeof hre,
    _options: HyperdriveDeployRuntimeOptions,
) => Promise<T>;

export type ValueOrHREFn<T extends unknown> = T | HREFn<T>;

export type ExtractValueOrHREFn<T extends ValueOrHREFn<unknown>> =
    T extends ValueOrHREFn<infer V> ? V : never;

export type ContractName = ArtifactsMap[keyof ArtifactsMap]["contractName"];

type FactoryConstructorArgs = ContractConstructorArgs<
    ArtifactsMap["HyperdriveFactory"]["abi"]
>;

export type HyperdriveFactoryConfig = {
    name: string;
    constructorArguments: ValueOrHREFn<FactoryConstructorArgs>;
    prepare?: HREFn;
    setup?: HREFn;
};

/**
 * Coordinator
 */

type CoordinatorPrefix<T extends string> = T extends `${infer P}Target0Deployer`
    ? P
    : never;

export type CoordinatorContract = ContractName &
    `${string}HyperdriveDeployerCoordinator`;

export type CoordinatorConstructorArgs<T extends ContractName> =
    ContractConstructorArgs<ArtifactsMap[T]["abi"]>;

export type CoreDeployerConstructorArgs<
    T extends CoordinatorPrefix<ContractName>,
> = ContractConstructorArgs<ArtifactsMap[`${T}HyperdriveCoreDeployer`]["abi"]>;

export type HyperdriveCoordinatorConfig<
    T extends CoordinatorPrefix<ContractName>,
> = {
    name: string;
    prefix: T;
    factoryAddress: ValueOrHREFn<Address>;
    targetCount: number;
    token?: ValueOrHREFn<Address>;
    extraConstructorArgs: ValueOrHREFn<CoreDeployerConstructorArgs<T>>;
    prepare?: HREFn;
    setup?: HREFn;
};

/**
 * Instances
 */
type InstancePrefix<T extends string> = T extends `${infer P}Target0`
    ? P
    : never;

type DeployTargetArguments = ContractFunctionArgs<
    ArtifactsMap["HyperdriveFactory"]["abi"],
    "nonpayable",
    "deployTarget"
>;

type DeployHyperdriveArguments = ContractFunctionArgs<
    ArtifactsMap["HyperdriveFactory"]["abi"],
    "payable",
    "deployAndInitialize"
>;

export type HyperdriveInstanceConfig<T extends InstancePrefix<ContractName>> = {
    name: string;
    prefix: T;
    coordinatorAddress: ValueOrHREFn<Address>;
    deploymentId: Hex;
    salt: Hex;
    extraData: Hex;
    contribution: bigint;
    fixedAPR: bigint;
    timestretchAPR: bigint;
    targetCount: number;
    poolDeployConfig: ValueOrHREFn<DeployTargetArguments[2]>;
    options: ValueOrHREFn<DeployHyperdriveArguments[7]>;
    prepare?: HREFn;
    setup?: HREFn;
};

export type HyperdriveConfig = {
    factories: HyperdriveFactoryConfig[];
    coordinators: HyperdriveCoordinatorConfig<
        CoordinatorPrefix<ContractName>
    >[];
    instances: HyperdriveInstanceConfig<InstancePrefix<ContractName>>[];
};

export const zHyperdriveFactoryDeployConfig = z.object({
    name: z.string(),
    prepare: z.custom<HREFn>().optional(),
    setup: z.custom<HREFn>().optional(),
    governance: zAddress,
    deployerCoordinatorManager: zAddress,
    hyperdriveGovernance: zAddress,
    defaultPausers: zAddress.array(),
    feeCollector: zAddress,
    sweepCollector: zAddress,
    checkpointDurationResolution: zDuration,
    minCheckpointDuration: zDuration,
    maxCheckpointDuration: zDuration,
    minPositionDuration: zDuration,
    maxPositionDuration: zDuration,
    minFixedAPR: zEther,
    maxFixedAPR: zEther,
    minTimeStretchAPR: zEther,
    maxTimeStretchAPR: zEther,
    minCircuitBreakerDelta: zEther,
    maxCircuitBreakerDelta: zEther,
    minFees: z.object({
        curve: zEther,
        flat: zEther,
        governanceLP: zEther,
        governanceZombie: zEther,
    }),
    maxFees: z.object({
        curve: zEther,
        flat: zEther,
        governanceLP: zEther,
        governanceZombie: zEther,
    }),
});

export type HyperdriveFactoryDeployConfigInput = z.input<
    typeof zHyperdriveFactoryDeployConfig
>;

export type HyperdriveFactoryDeployConfig = z.infer<
    typeof zHyperdriveFactoryDeployConfig
>;

export const zHyperdriveCoordinatorDeployConfig = z.object({
    name: z.string(),
    contract: z.string(),
    factoryName: z.string(),
    targetCount: z.number(),
    lpMath: z.string({ description: "name of the LPMath contract to link" }),
    prepare: z.custom<HREFn>().optional(),
    setup: z.custom<HREFn>().optional(),
    coreConstructorArguments: z
        .custom<
            (
                _hre: typeof hre,
                _options: HyperdriveDeployRuntimeOptions,
            ) => Promise<any[]>
        >()
        .optional(),
    targetConstructorArguments: z
        .custom<
            (
                _hre: typeof hre,
                _options: HyperdriveDeployRuntimeOptions,
            ) => Promise<any[]>
        >()
        .optional(),
    token: z
        .union([
            zAddress,
            z.object({
                name: z.string(),
                deploy: z.custom<HREFn>().optional(),
            }),
        ])
        .optional(),
});

export type HyperdriveCoordinatorDeployConfigInput = z.input<
    typeof zHyperdriveCoordinatorDeployConfig
>;

export type HyperdriveCoordinatorDeployConfig = z.infer<
    typeof zHyperdriveCoordinatorDeployConfig
>;

export const zHyperdriveInstanceDeployConfig = z.object({
    name: z.string(),
    contract: z.string(),
    coordinatorName: z.string(),
    prepare: z.custom<HREFn>().optional(),
    setup: z.custom<HREFn>().optional(),
    deploymentId: zBytes32.default(
        toHex(new Date().toISOString(), { size: 32 }),
    ),
    salt: zBytes32,
    contribution: zEther,
    fixedAPR: zEther,
    timestretchAPR: zEther,
    options: z.object({
        destination: zAddress.optional(),
        asBase: z.boolean().default(true),
        extraData: zHex.default("0x"),
    }),
    poolDeployConfig: z
        .object({
            baseToken: z
                .union([
                    zAddress,
                    z.object({
                        name: z.string(),
                        deploy: z.custom<HREFn>().optional(),
                    }),
                ])
                .optional(),
            vaultSharesToken: z
                .union([
                    zAddress,
                    z.object({
                        name: z.string(),
                        deploy: z.custom<HREFn>().optional(),
                    }),
                ])
                .optional(),
            minimumShareReserves: zEther,
            minimumTransactionAmount: zEther,
            circuitBreakerDelta: zEther,
            positionDuration: zDuration,
            checkpointDuration: zDuration,
            timeStretch: zEther,
            governance: zAddress,
            feeCollector: zAddress,
            sweepCollector: zAddress,
            fees: z.object({
                curve: zEther,
                flat: zEther,
                governanceLP: zEther,
                governanceZombie: zEther,
            }),
        })
        .transform((v) => ({
            ...v,
            fees: {
                ...v.fees,
                // flat fee needs to be adjusted to a yearly basis
                flat:
                    v.fees.flat /
                    (BigInt(dayjs.duration(365, "days").asSeconds()) /
                        v.positionDuration),
            },
        })),
});

export type HyperdriveInstanceDeployConfigInput = z.input<
    typeof zHyperdriveInstanceDeployConfig
>;

export type HyperdriveInstanceDeployConfig = z.infer<
    typeof zHyperdriveInstanceDeployConfig
>;

export const zHyperdriveDeployConfig = z
    .object({
        factories: zHyperdriveFactoryDeployConfig.array().optional(),
        coordinators: zHyperdriveCoordinatorDeployConfig.array().optional(),
        instances: zHyperdriveInstanceDeployConfig.array().optional(),
    })
    .optional();

export type HyperdriveDeployConfigInput = z.input<
    typeof zHyperdriveDeployConfig
>;
export type HyperdriveDeployConfig = z.infer<typeof zHyperdriveDeployConfig>;
