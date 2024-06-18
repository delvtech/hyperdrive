import dayjs from "dayjs";
import duration, { DurationUnitType } from "dayjs/plugin/duration";
import hre from "hardhat";
import { ArtifactsMap } from "hardhat/types";
import {
    Address,
    ContractConstructorArgs,
    ContractFunctionArgs,
    Hex,
} from "viem";
import { z } from "zod";
import { HyperdriveDeployRuntimeOptions } from "./environment-extensions";
dayjs.extend(duration);

/**
 * Specifies a 42 character string with the prefix '0x'
 */
export const zAddress = z.custom<`0x${string}`>(
    (v) => typeof v === "string" && /^0x[\da-fA-F]{40}$/g.test(v),
);

/**
 * Accepted lengths of time for duration specification
 */
export const durationUnits = [
    "minute",
    "minutes",
    "hour",
    "hours",
    "day",
    "days",
    "week",
    "weeks",
    "year",
    "years",
];

export type DurationString = `${number} ${(typeof durationUnits)[number]}`;

/**
 * Accepts durations of the following form using {@link durationUnits}
 */
export const parseDuration = (d: DurationString) => {
    const parts = d.split(" ");
    if (parts.length != 2) throw new Error(`invalid duration string "${d}"`);
    const [quantityString, unit] = parts;
    if (!durationUnits.includes(unit)) throw new Error(`invalid unit ${unit}`);
    if (isNaN(parseInt(quantityString)))
        throw new Error(`invalid quantity ${quantityString}`);
    return BigInt(
        dayjs
            .duration(parseInt(quantityString), unit as DurationUnitType)
            .asSeconds(),
    );
};

/**
 * A function that receives the {@link HardhatRuntimeEnvironment}.
 * Typically used as a hook in configuration for users to deploy contracts or read state.
 */
export type HREFn<T extends unknown = void> = (
    _hre: typeof hre,
    _options: HyperdriveDeployRuntimeOptions,
) => Promise<T>;

/**
 * Union type of any value and a {@link HREFn} that returns the same value.
 */
export type ValueOrHREFn<T extends unknown> = T | HREFn<T>;

/**
 * Utility type for extracting the inner value type for {@link ValueOrHREFn}.
 */
export type ExtractValueOrHREFn<T extends ValueOrHREFn<unknown>> =
    T extends ValueOrHREFn<infer V> ? V : never;

/**
 * Intersection type of all contract names. These names are derived from compilation artifacts which
 * ensures they stay up-to-date.
 */
export type ContractName = ArtifactsMap[keyof ArtifactsMap]["contractName"];

/**
 * Constructor argument types for the HyperdriveCheckpointRewarder.
 */
export type CheckpointRewarderConstructorArgs = ContractConstructorArgs<
    ArtifactsMap["HyperdriveCheckpointRewarder"]["abi"]
>;

/**
 * Configuration for a `HyperdriveCheckpointRewarder` instance.
 */
export type HyperdriveCheckpointRewarderConfig = {
    name: string;
    constructorArguments: ValueOrHREFn<CheckpointRewarderConstructorArgs>;
    prepare?: HREFn;
    setup?: HREFn;
};

/**
 * Constructor argument types for the HyperdriveCheckpointSubrewarder.
 */
export type CheckpointSubrewarderConstructorArgs = ContractConstructorArgs<
    ArtifactsMap["HyperdriveCheckpointSubrewarder"]["abi"]
>;

/**
 * Configuration for a `HyperdriveCheckpointSubrewarder` instance.
 */
export type HyperdriveCheckpointSubrewarderConfig = {
    name: string;
    constructorArguments: ValueOrHREFn<CheckpointSubrewarderConstructorArgs>;
    prepare?: HREFn;
    setup?: HREFn;
};

/**
 * Constructor argument types for the HyperdriveFactory.
 */
export type FactoryConstructorArgs = ContractConstructorArgs<
    ArtifactsMap["HyperdriveFactory"]["abi"]
>;

/**
 * Configuration for a `HyperdriveFactory` instance.
 */
export type HyperdriveFactoryConfig = {
    name: string;
    constructorArguments: ValueOrHREFn<FactoryConstructorArgs>;
    prepare?: HREFn;
    setup?: HREFn;
};

/**
 * Contract name prefix for a `HyperdriveDeployerCoordinator`. The type uses inferencing from the
 * `Target0Deployer` contract suffix instead of the `HyperdriveDeployerCoordinator` suffix to
 * eliminate undesireable interfaces and test contracts as candidates.
 */
type CoordinatorPrefix<T extends string> = T extends `${infer P}Target0Deployer`
    ? P
    : never;

/**
 * Constructor argument types for a `HyperdriveCoreDeployer` instance.
 */
export type CoreDeployerConstructorArgs<
    T extends CoordinatorPrefix<ContractName>,
> = ContractConstructorArgs<ArtifactsMap[`${T}HyperdriveCoreDeployer`]["abi"]>;

/**
 * Configuration for a `HyperdriveDeployerCoordinator` instance.
 */
export type HyperdriveCoordinatorConfig<
    T extends CoordinatorPrefix<ContractName>,
> = {
    name: string;
    prefix: T;
    factoryAddress: ValueOrHREFn<Address>;
    targetCount: number;
    token?: ValueOrHREFn<Address>;
    extraConstructorArgs?: ValueOrHREFn<CoreDeployerConstructorArgs<T>>;
    prepare?: HREFn;
    setup?: HREFn;
};

/**
 * Contract name prefix for a `Hyperdrive` instance. The type uses inferencing from the
 * `Target0` contract suffix instead of the `Hyperdrive` suffix to
 * eliminate undesireable interfaces and test contracts as candidates.
 */
type InstancePrefix<T extends string> = T extends `${infer P}Target0`
    ? `${P}Hyperdrive` extends ContractName
        ? P
        : never
    : never;

/**
 * `deployTarget` function argument types. These are referenced by various
 * fields in the {@link HyperdriveInstanceConfig}.
 */
type DeployTargetArguments = ContractFunctionArgs<
    ArtifactsMap["HyperdriveFactory"]["abi"],
    "nonpayable",
    "deployTarget"
>;

/**
 * `deployAndInitialize` function argument types. These are referenced by various fields in the
 * {@link HyperdriveInstanceConfig}
 */
type DeployHyperdriveArguments = ContractFunctionArgs<
    ArtifactsMap["HyperdriveFactory"]["abi"],
    "payable",
    "deployAndInitialize"
>;

/**
 * Configuration required to deploy a `Hyperdrive` contract instance.
 */
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
    poolDeployConfig: ValueOrHREFn<DeployTargetArguments[2]>;
    options: ValueOrHREFn<DeployHyperdriveArguments[8]>;
    prepare?: HREFn;
    setup?: HREFn;
};

/**
 * Unified description of `Hyperdrive` contract deployments for a network.
 */
export type HyperdriveConfig = {
    checkpointRewarders: HyperdriveCheckpointRewarderConfig[];
    checkpointSubrewarders: HyperdriveCheckpointSubrewarderConfig[];
    factories: HyperdriveFactoryConfig[];
    coordinators: HyperdriveCoordinatorConfig<
        CoordinatorPrefix<ContractName>
    >[];
    instances: HyperdriveInstanceConfig<InstancePrefix<ContractName>>[];
};
