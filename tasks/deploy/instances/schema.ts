import dayjs from "dayjs";
import { z } from "zod";
import {
  zBytes32,
  zEther,
  zAddress,
  zHex,
  zDuration,
  Prettify,
} from "../utils";
import { zeroAddress } from "viem";

// Schema for hyperdrive instance configuration (specified in hardhat.config.ts)
export const zInstanceDeployConfig = z.object({
  name: z.string(),
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
      baseToken: zAddress.optional(),
      vaultSharesToken: zAddress.optional(),
      minimumShareReserves: zEther,
      minimumTransactionAmount: zEther,
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

export type InstanceDeployConfigInput = z.input<typeof zInstanceDeployConfig>;
export type InstanceDeployConfig = z.infer<typeof zInstanceDeployConfig>;

export type PoolDeployConfig = Prettify<
  Required<InstanceDeployConfig["poolDeployConfig"]> & {
    linkerFactory: `0x${string}`;
    linkerCodeHash: `0x${string}`;
  }
>;

export type PoolDeployConfig2 = Prettify<
  Required<InstanceDeployConfig["poolDeployConfig"]> & {
    linkerFactory: string;
    linkerCodeHash: string;
  }
>;

export type PoolConfig = Prettify<
  PoolDeployConfig & {
    initialVaultSharePrice: bigint;
  }
>;

export type DeployInstanceParams = {
  name: string;
  admin?: string;
};
