import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox-viem";
import "@nomicfoundation/hardhat-viem";
import "dotenv/config";
import "hardhat-deploy";
import { HardhatUserConfig } from "hardhat/config";
import baseConfig from "./hardhat.config";
import "./tasks";
import {
    SEPOLIA_DAI_14DAY,
    SEPOLIA_DAI_30DAY,
    SEPOLIA_ERC4626_COORDINATOR,
    SEPOLIA_EZETH_14DAY,
    SEPOLIA_EZETH_30DAY,
    SEPOLIA_EZETH_COORDINATOR,
    SEPOLIA_FACTORY,
    SEPOLIA_MORPHO_DAI_14DAY,
    SEPOLIA_MORPHO_DAI_30DAY,
    SEPOLIA_RETH_14DAY,
    SEPOLIA_RETH_30DAY,
    SEPOLIA_RETH_COORDINATOR,
    SEPOLIA_STETH_14DAY,
    SEPOLIA_STETH_30DAY,
    SEPOLIA_STETH_COORDINATOR,
} from "./tasks/deploy/config/";

const { env } = process;
let DEFAULT_PK =
    "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

const config: HardhatUserConfig = {
    ...baseConfig,
    networks: {
        hardhat: {
            accounts: [
                {
                    privateKey: env.PRIVATE_KEY ?? DEFAULT_PK,
                    balance: "1000000000000000000",
                },
            ],
            hyperdriveDeploy: {
                factories: [SEPOLIA_FACTORY],
                coordinators: [
                    SEPOLIA_ERC4626_COORDINATOR,
                    SEPOLIA_STETH_COORDINATOR,
                    SEPOLIA_RETH_COORDINATOR,
                    SEPOLIA_EZETH_COORDINATOR,
                ],
                instances: [
                    SEPOLIA_DAI_14DAY,
                    SEPOLIA_DAI_30DAY,
                    SEPOLIA_EZETH_14DAY,
                    SEPOLIA_EZETH_30DAY,
                    SEPOLIA_MORPHO_DAI_14DAY,
                    SEPOLIA_MORPHO_DAI_30DAY,
                    SEPOLIA_RETH_14DAY,
                    SEPOLIA_RETH_30DAY,
                    SEPOLIA_STETH_14DAY,
                    SEPOLIA_STETH_30DAY,
                ],
            },
        },
        sepolia: {
            live: true,
            chainId: 11155111,
            accounts: [env.DEPLOYER_PRIVATE_KEY ?? DEFAULT_PK],
            url: env.SEPOLIA_RPC_URL ?? "",
            verify: {
                etherscan: {
                    apiKey: env.ETHERSCAN_API_KEY ?? DEFAULT_PK,
                    apiUrl: "https://api-sepolia.etherscan.io",
                },
            },
            hyperdriveDeploy: {
                factories: [SEPOLIA_FACTORY],
                coordinators: [
                    SEPOLIA_ERC4626_COORDINATOR,
                    SEPOLIA_STETH_COORDINATOR,
                    SEPOLIA_RETH_COORDINATOR,
                    SEPOLIA_EZETH_COORDINATOR,
                ],
                instances: [
                    SEPOLIA_DAI_14DAY,
                    SEPOLIA_DAI_30DAY,
                    SEPOLIA_EZETH_14DAY,
                    SEPOLIA_EZETH_30DAY,
                    SEPOLIA_MORPHO_DAI_14DAY,
                    SEPOLIA_MORPHO_DAI_30DAY,
                    SEPOLIA_RETH_14DAY,
                    SEPOLIA_RETH_30DAY,
                    SEPOLIA_STETH_14DAY,
                    SEPOLIA_STETH_30DAY,
                ],
            },
        },
        base_sepolia: {
            live: true,
            accounts: [env.DEPLOYER_PRIVATE_KEY ?? DEFAULT_PK],
            url: env.BASE_SEPOLIA_RPC_URL ?? "",
            verify: {
                etherscan: {
                    apiKey: env.ETHERSCAN_BASE_API_KEY ?? "",
                    apiUrl: "https://api-sepolia.basescan.org",
                },
            },
            hyperdriveDeploy: {
                factories: [SEPOLIA_FACTORY],
                coordinators: [
                    SEPOLIA_ERC4626_COORDINATOR,
                    SEPOLIA_STETH_COORDINATOR,
                    SEPOLIA_RETH_COORDINATOR,
                    SEPOLIA_EZETH_COORDINATOR,
                ],
                instances: [
                    SEPOLIA_DAI_14DAY,
                    SEPOLIA_DAI_30DAY,
                    SEPOLIA_EZETH_14DAY,
                    SEPOLIA_EZETH_30DAY,
                    SEPOLIA_MORPHO_DAI_14DAY,
                    SEPOLIA_MORPHO_DAI_30DAY,
                    SEPOLIA_RETH_14DAY,
                    SEPOLIA_RETH_30DAY,
                    SEPOLIA_STETH_14DAY,
                    SEPOLIA_STETH_30DAY,
                ],
            },
        },
    },
};

export default config;