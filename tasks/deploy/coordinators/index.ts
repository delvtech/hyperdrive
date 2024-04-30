import { z } from "zod";
import { zAddress } from "../utils";

export * from "./all";
export * from "./erc4626";
export * from "./reth";
export * from "./steth";

export const zCoordinatorDeployConfig = z.object({
  reth: zAddress.optional(),
  lido: zAddress.optional(),
});

export type CoordinatorDeployConfigInput = z.input<
  typeof zCoordinatorDeployConfig
>;

export type CoordinatorDeployConfig = z.infer<typeof zCoordinatorDeployConfig>;
