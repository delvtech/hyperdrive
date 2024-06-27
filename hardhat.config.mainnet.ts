import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-viem";
import "dotenv/config";
import "hardhat-deploy";
import { HardhatUserConfig } from "hardhat/config";
import baseConfig from "./hardhat.config";
import "./tasks";
import {
    MAINNET_DAI_182DAY,
    MAINNET_ERC4626_COORDINATOR,
    MAINNET_FACTORY,
    MAINNET_STETH_182DAY,
    MAINNET_STETH_COORDINATOR,
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
                    MAINNET_STETH_COORDINATOR,
                ],
                instances: [MAINNET_DAI_182DAY, MAINNET_STETH_182DAY],
                checkpointRewarders: [],
                checkpointSubrewarders: [],
            },
        },
    },
};

export default config;
