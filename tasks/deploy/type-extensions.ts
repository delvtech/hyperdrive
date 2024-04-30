// If your plugin extends types from another plugin, you should import the plugin here.

// To extend one of Hardhat's types, you need to import the module where it has been defined, and redeclare it.
import "hardhat/types/config";
import "hardhat/types/runtime";
import {
  FactoryDeployConfig,
  FactoryDeployConfigInput,
  zFactoryDeployConfig,
} from "./factory";
import {
  InstanceDeployConfig,
  InstanceDeployConfigInput,
  zInstanceDeployConfig,
} from "./instance";
import { extendConfig } from "hardhat/config";
import {
  HardhatConfig,
  HardhatUserConfig,
  HttpNetworkUserConfig,
} from "hardhat/types/config";
import {
  ERC4626InstanceDeployConfig,
  ERC4626InstanceDeployConfigInput,
  zERC4626InstanceDeployConfig,
} from "./instances";
import {
  CoordinatorDeployConfig,
  CoordinatorDeployConfigInput,
  zCoordinatorDeployConfig,
} from "./coordinators";

declare module "hardhat/types/config" {
  // We extend the user's HardhatNetworkUserConfig with our factory and instance configuration inputs.
  // These will be parsed, validated, and written to the global configuration.
  export interface HttpNetworkUserConfig {
    factory?: FactoryDeployConfigInput;
    coordinators?: CoordinatorDeployConfigInput;
    instances?: {
      erc4626?: ERC4626InstanceDeployConfigInput[];
    };
  }
  export interface HardhatNetworkUserConfig {
    factory?: FactoryDeployConfigInput;
    coordinators?: CoordinatorDeployConfigInput;
    instances?: {
      erc4626?: ERC4626InstanceDeployConfigInput[];
    };
  }

  // Extend the global config with output types.
  export interface HttpNetworkConfig {
    factory?: FactoryDeployConfig;
    coordinators?: CoordinatorDeployConfig;
    instances?: {
      erc4626?: ERC4626InstanceDeployConfig[];
    };
  }
  export interface HardhatNetworkConfig {
    factory?: FactoryDeployConfig;
    coordinators?: CoordinatorDeployConfig;
    instances?: {
      erc4626?: ERC4626InstanceDeployConfig[];
    };
  }
}

extendConfig(
  (config: HardhatConfig, userConfig: Readonly<HardhatUserConfig>) => {
    Object.entries(
      userConfig.networks as Record<string, HttpNetworkUserConfig>,
    ).forEach(([k, v]) => {
      config.networks[k].factory = zFactoryDeployConfig.parse(v.factory);
      if (v.coordinators) {
        config.networks[k].coordinators = zCoordinatorDeployConfig.parse(
          v.coordinators,
        );
      }
      config.networks[k].instances = {
        erc4626: v.instances?.erc4626?.map((i) =>
          zERC4626InstanceDeployConfig.parse(i),
        ),
      };
    });
  },
);
