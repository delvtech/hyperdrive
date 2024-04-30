import { z } from "zod";
import { Prettify } from "../utils";
import { zRETHCoordinatorDeployConfig } from "./reth";
import { zStETHCoordinatorDeployConfig } from "./steth";

export const zCoordinatorDeployConfig = zRETHCoordinatorDeployConfig.merge(
  zStETHCoordinatorDeployConfig,
);

export type CoordinatorDeployConfigInput = Prettify<
  z.input<typeof zCoordinatorDeployConfig>
>;

export type CoordinatorDeployConfig = Prettify<
  z.infer<typeof zCoordinatorDeployConfig>
>;
