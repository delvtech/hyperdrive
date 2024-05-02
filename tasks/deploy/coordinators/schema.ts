import { z } from "zod";
import { Prettify } from "../types";
import { zRETHCoordinatorDeployConfig } from "./reth";
import { zStETHCoordinatorDeployConfig } from "./steth";
import { zEzETHCoordinatorDeployConfig } from "./ezeth";

export const zCoordinatorDeployConfig = zRETHCoordinatorDeployConfig
  .merge(zStETHCoordinatorDeployConfig)
  .merge(zEzETHCoordinatorDeployConfig);

export type CoordinatorDeployConfigInput = Prettify<
  z.input<typeof zCoordinatorDeployConfig>
>;

export type CoordinatorDeployConfig = Prettify<
  z.infer<typeof zCoordinatorDeployConfig>
>;
