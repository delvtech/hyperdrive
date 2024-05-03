import { z } from "zod";
import { Prettify } from "../types";
import { zEzETHCoordinatorDeployConfig } from "./ezeth";
import { zRETHCoordinatorDeployConfig } from "./reth";
import { zStETHCoordinatorDeployConfig } from "./steth";

export const zCoordinatorDeployConfig = zRETHCoordinatorDeployConfig
    .merge(zStETHCoordinatorDeployConfig)
    .merge(zEzETHCoordinatorDeployConfig);

export type CoordinatorDeployConfigInput = Prettify<
    z.input<typeof zCoordinatorDeployConfig>
>;

export type CoordinatorDeployConfig = Prettify<
    z.infer<typeof zCoordinatorDeployConfig>
>;
