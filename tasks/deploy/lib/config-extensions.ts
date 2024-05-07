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
    HyperdriveDeployConfig,
    HyperdriveDeployConfigInput,
    zHyperdriveDeployConfig,
} from "./schemas";

declare module "hardhat/types/config" {
    // We extend the user's HardhatNetworkUserConfig with our factory and instance configuration inputs.
    // These will be parsed, validated, and written to the global configuration.
    export interface HttpNetworkUserConfig {
        hyperdriveDeploy?: HyperdriveDeployConfigInput;
    }
    export interface HardhatNetworkUserConfig {
        hyperdriveDeploy?: HyperdriveDeployConfigInput;
    }

    // Extend the global config with output types.
    export interface HttpNetworkConfig {
        hyperdriveDeploy?: HyperdriveDeployConfig;
    }
    export interface HardhatNetworkConfig {
        hyperdriveDeploy?: HyperdriveDeployConfig;
    }
}

// Parsing logic for the various configuration fields.
extendConfig(
    (config: HardhatConfig, userConfig: Readonly<HardhatUserConfig>) => {
        Object.entries(
            userConfig.networks as Record<string, HttpNetworkUserConfig>,
        ).forEach(([k, v]) => {
            config.networks[k].hyperdriveDeploy = v
                ? zHyperdriveDeployConfig.parse(v.hyperdriveDeploy)
                : undefined;
        });
    },
);
