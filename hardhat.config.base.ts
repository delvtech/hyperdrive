import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-viem";
import "dotenv/config";
import "hardhat-deploy";
import { HardhatUserConfig } from "hardhat/config";
import baseConfig from "./hardhat.config";
import "./tasks";
import {
    BASE_CBETH_182DAY,
    BASE_CHAINLINK_COORDINATOR,
    BASE_ERC4626_COORDINATOR,
    BASE_FACTORY,
    BASE_MOONWELL_ETH_182DAY,
    BASE_MOONWELL_EURC_182DAY,
    BASE_MOONWELL_USDC_182DAY,
    BASE_MORPHO_BLUE_COORDINATOR,
    BASE_SNARS_30DAY,
    BASE_STK_WELL_182DAY,
    BASE_STK_WELL_COORDINATOR,
} from "./tasks/deploy/config/base";
import { BASE_AERODROME_LP_AERO_USDC_91DAY } from "./tasks/deploy/config/base/aerodrome-lp-aero-usdc-91day";
import { BASE_AERODROME_LP_COORDINATOR } from "./tasks/deploy/config/base/aerodrome-lp-coordinator";
import { BASE_MORPHO_BLUE_CBETH_USDC_182DAY } from "./tasks/deploy/config/base/morpho-blue-cbeth-usdc-182day";

const { env } = process;

const config: HardhatUserConfig = {
    ...baseConfig,
    networks: {
        base: {
            live: true,
            url: env.HYPERDRIVE_ETHEREUM_URL!,
            accounts: [env.DEPLOYER_PRIVATE_KEY!, env.PAUSER_PRIVATE_KEY!],
            hyperdriveDeploy: {
                factories: [BASE_FACTORY],
                coordinators: [
                    BASE_CHAINLINK_COORDINATOR,
                    BASE_MORPHO_BLUE_COORDINATOR,
                    BASE_ERC4626_COORDINATOR,
                    BASE_STK_WELL_COORDINATOR,
                    BASE_AERODROME_LP_COORDINATOR,
                ],
                instances: [
                    BASE_CBETH_182DAY,
                    BASE_MORPHO_BLUE_CBETH_USDC_182DAY,
                    BASE_MOONWELL_ETH_182DAY,
                    BASE_STK_WELL_182DAY,
                    BASE_SNARS_30DAY,
                    BASE_MOONWELL_EURC_182DAY,
                    BASE_MOONWELL_USDC_182DAY,
                    BASE_AERODROME_LP_AERO_USDC_91DAY,
                ],
                checkpointRewarders: [],
                checkpointSubrewarders: [],
            },
        },
    },
    etherscan: {
        customChains: [
            {
                network: "base",
                chainId: 8453,
                urls: {
                    apiURL: "https://api.basescan.org/api",
                    browserURL: "https://basescan.org",
                },
            },
        ],
        apiKey: {
            base: process.env.BASESCAN_API_KEY || "",
        },
    },
};

export default config;
