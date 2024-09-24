import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-viem";
import "dotenv/config";
import "hardhat-deploy";
import { HardhatUserConfig } from "hardhat/config";
import baseConfig from "./hardhat.config";
import "./tasks";
import {
    MAINNET_EETH_182DAY,
    MAINNET_EETH_COORDINATOR,
    MAINNET_EZETH_182DAY,
    MAINNET_EZETH_COORDINATOR,
    MAINNET_FACTORY,
    MAINNET_MORPHO_BLUE_COORDINATOR,
    MAINNET_MORPHO_BLUE_SUSDE_DAI_182DAY,
    MAINNET_MORPHO_BLUE_USDE_DAI_182DAY,
    MAINNET_MORPHO_BLUE_WSTETH_USDC_182DAY,
    MAINNET_RETH_182DAY,
    MAINNET_RETH_COORDINATOR,
} from "./tasks/deploy/config/mainnet";

const { env } = process;
let DEFAULT_PK =
    "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

const config: HardhatUserConfig = {
    ...baseConfig,
    networks: {
        mainnet_fork: {
            live: false,
            url: env.HYPERDRIVE_ETHEREUM_URL!,
            accounts: [env.DEPLOYER_PRIVATE_KEY ?? DEFAULT_PK],
            hyperdriveDeploy: {
                factories: [MAINNET_FACTORY],
                coordinators: [
                    MAINNET_EZETH_COORDINATOR,
                    MAINNET_RETH_COORDINATOR,
                    MAINNET_MORPHO_BLUE_COORDINATOR,
                    MAINNET_EETH_COORDINATOR,
                ],
                instances: [
                    MAINNET_EZETH_182DAY,
                    MAINNET_RETH_182DAY,
                    MAINNET_MORPHO_BLUE_SUSDE_DAI_182DAY,
                    MAINNET_MORPHO_BLUE_USDE_DAI_182DAY,
                    MAINNET_MORPHO_BLUE_WSTETH_USDC_182DAY,
                    MAINNET_EETH_182DAY,
                ],
                checkpointRewarders: [],
                checkpointSubrewarders: [],
            },
        },
    },
};

export default config;
