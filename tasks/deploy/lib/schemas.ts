import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import hre from "hardhat";
import { z } from "zod";
import { zAddress, zBytes32, zDuration, zEther, zHex } from "./types";
dayjs.extend(duration);

export const zHyperdriveFactoryDeployConfig = z.object({
    name: z.string(),
    prepare: z.custom<(_hre: typeof hre) => Promise<void>>().optional(),
    setup: z.custom<(_hre: typeof hre) => Promise<void>>().optional(),
    governance: zAddress,
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
    prepare: z.custom<(_hre: typeof hre) => Promise<void>>().optional(),
    setup: z.custom<(_hre: typeof hre) => Promise<void>>().optional(),
    coreConstructorArguments: z
        .custom<(_hre: typeof hre) => Promise<any[]>>()
        .optional(),
    targetConstructorArguments: z
        .custom<(_hre: typeof hre) => Promise<any[]>>()
        .optional(),
    token: z
        .union([
            zAddress,
            z.object({
                name: z.string(),
                deploy: z
                    .custom<(_hre: typeof hre) => Promise<void>>()
                    .optional(),
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
    prepare: z.custom<(_hre: typeof hre) => Promise<void>>().optional(),
    setup: z.custom<(_hre: typeof hre) => Promise<void>>().optional(),
    deploymentId: zBytes32,
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
                        deploy: z
                            .custom<(_hre: typeof hre) => Promise<void>>()
                            .optional(),
                    }),
                ])
                .optional(),
            vaultSharesToken: z
                .union([
                    zAddress,
                    z.object({
                        name: z.string(),
                        deploy: z
                            .custom<(_hre: typeof hre) => Promise<void>>()
                            .optional(),
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
