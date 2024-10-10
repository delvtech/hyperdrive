import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-viem";
import "dotenv/config";
import "hardhat-deploy";
import { HardhatUserConfig } from "hardhat/config";
import baseConfig from "./hardhat.config";
import "./tasks";
import {
    MAINNET_ERC4626_COORDINATOR,
    MAINNET_EZETH_182DAY,
    MAINNET_EZETH_COORDINATOR,
    MAINNET_FACTORY,
    MAINNET_MORPHO_BLUE_COORDINATOR,
    MAINNET_MORPHO_BLUE_SUSDE_DAI_182DAY,
    MAINNET_MORPHO_BLUE_USDE_DAI_182DAY,
    MAINNET_MORPHO_BLUE_WSTETH_USDA_182DAY,
    MAINNET_RETH_182DAY,
    MAINNET_RETH_COORDINATOR,
    MAINNET_STUSD_182DAY,
    MAINNET_SUSDE_182DAY,
} from "./tasks/deploy/config/mainnet";

const { env } = process;

const config: HardhatUserConfig = {
    ...baseConfig,
    networks: {
        mainnet: {
            live: true,
            url: env.HYPERDRIVE_ETHEREUM_URL!,
            accounts: [env.DEPLOYER_PRIVATE_KEY!, env.PAUSER_PRIVATE_KEY!],
            hyperdriveDeploy: {
                factories: [MAINNET_FACTORY],
                coordinators: [
                    MAINNET_ERC4626_COORDINATOR,
                    MAINNET_EZETH_COORDINATOR,
                    MAINNET_RETH_COORDINATOR,
                    MAINNET_MORPHO_BLUE_COORDINATOR,
                ],
                instances: [
                    MAINNET_EZETH_182DAY,
                    MAINNET_RETH_182DAY,
                    MAINNET_MORPHO_BLUE_SUSDE_DAI_182DAY,
                    MAINNET_MORPHO_BLUE_USDE_DAI_182DAY,
                    MAINNET_MORPHO_BLUE_WSTETH_USDA_182DAY,
                    MAINNET_STUSD_182DAY,
                    MAINNET_SUSDE_182DAY,
                ],
                checkpointRewarders: [],
                checkpointSubrewarders: [],
            },
        },
    },
};

export default config;
