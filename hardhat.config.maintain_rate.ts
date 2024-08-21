import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-viem";
import "dotenv/config";
import "hardhat-deploy";
import { HardhatUserConfig } from "hardhat/config";
import baseConfig from "./hardhat.config";
import "./tasks";

const { env } = process;

const config: HardhatUserConfig = {
    ...baseConfig,
    networks: {
        mainnet_fork: {
            live: false,
            url: env.HYPERDRIVE_ETHEREUM_URL ?? "http://anvil:8545",
        },
    },
};

export default config;
