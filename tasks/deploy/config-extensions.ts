// To extend one of Hardhat's types, you need to import the module where it has been defined, and redeclare it.
import { extendConfig } from "hardhat/config";
import "hardhat/types/config";
import {
    HardhatConfig,
    HardhatUserConfig,
    HttpNetworkUserConfig,
} from "hardhat/types/config";
import "hardhat/types/runtime";
import {
    CoordinatorDeployConfig,
    StETHCoordinatorDeployConfigInput,
    zCoordinatorDeployConfig,
} from "./coordinators";
import {
    FactoryDeployConfig,
    FactoryDeployConfigInput,
    zFactoryDeployConfig,
} from "./factory";
import {
    ERC4626InstanceDeployConfig,
    ERC4626InstanceDeployConfigInput,
    zERC4626InstanceDeployConfig,
} from "./instances";
import {
    EzETHInstanceDeployConfig,
    EzETHInstanceDeployConfigInput,
    zEzETHInstanceDeployConfig,
} from "./instances/ezeth";
import {
    RETHInstanceDeployConfig,
    RETHInstanceDeployConfigInput,
    zRETHInstanceDeployConfig,
} from "./instances/reth";
import {
    StETHInstanceDeployConfig,
    StETHInstanceDeployConfigInput,
    zStETHInstanceDeployConfig,
} from "./instances/steth";

declare module "hardhat/types/config" {
    // We extend the user's HardhatNetworkUserConfig with our factory and instance configuration inputs.
    // These will be parsed, validated, and written to the global configuration.
    export interface HttpNetworkUserConfig {
        factory?: FactoryDeployConfigInput;
        coordinators?: StETHCoordinatorDeployConfigInput;
        instances?: {
            erc4626?: ERC4626InstanceDeployConfigInput[];
            steth?: StETHInstanceDeployConfigInput[];
            reth?: RETHInstanceDeployConfigInput[];
        };
    }
    export interface HardhatNetworkUserConfig {
        factory?: FactoryDeployConfigInput;
        coordinators?: StETHCoordinatorDeployConfigInput;
        instances?: {
            erc4626?: ERC4626InstanceDeployConfigInput[];
            steth?: StETHInstanceDeployConfigInput[];
            reth?: RETHInstanceDeployConfigInput[];
            ezeth?: EzETHInstanceDeployConfigInput[];
        };
    }

    // Extend the global config with output types.
    export interface HttpNetworkConfig {
        factory?: FactoryDeployConfig;
        coordinators?: CoordinatorDeployConfig;
        instances?: {
            erc4626?: ERC4626InstanceDeployConfig[];
            steth?: StETHInstanceDeployConfig[];
            reth?: RETHInstanceDeployConfig[];
            ezeth?: EzETHInstanceDeployConfig[];
        };
    }
    export interface HardhatNetworkConfig {
        factory?: FactoryDeployConfig;
        coordinators?: CoordinatorDeployConfig;
        instances?: {
            erc4626?: ERC4626InstanceDeployConfig[];
            steth?: StETHInstanceDeployConfig[];
            reth?: RETHInstanceDeployConfig[];
            ezeth?: EzETHInstanceDeployConfig[];
        };
    }
}

// Parsing logic for the various configuration fields.
extendConfig(
    (config: HardhatConfig, userConfig: Readonly<HardhatUserConfig>) => {
        Object.entries(
            userConfig.networks as Record<string, HttpNetworkUserConfig>,
        ).forEach(([k, v]) => {
            config.networks[k].factory = zFactoryDeployConfig.parse(v.factory);
            if (v.coordinators) {
                config.networks[k].coordinators =
                    zCoordinatorDeployConfig.parse(v.coordinators);
            }
            config.networks[k].instances = {
                erc4626: v.instances?.erc4626?.map((i) =>
                    zERC4626InstanceDeployConfig.parse(i),
                ),
                steth: v.instances?.steth?.map((i) =>
                    zStETHInstanceDeployConfig.parse(i),
                ),
                ezeth: v.instances?.steth?.map((i) =>
                    zEzETHInstanceDeployConfig.parse(i),
                ),
                reth: v.instances?.reth?.map((i) =>
                    zRETHInstanceDeployConfig.parse(i),
                ),
            };
        });
    },
);
